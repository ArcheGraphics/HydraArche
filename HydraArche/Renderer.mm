//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

#define GL_SILENCE_DEPRECATION 1

#import "Renderer.h"
#import "Camera.h"

#include "pxr/pxr.h"
#include <pxr/base/gf/camera.h>
#include <pxr/base/gf/vec3f.h>
#include <pxr/base/plug/plugin.h>
#include "pxr/base/plug/registry.h"
#include <pxr/usd/usd/prim.h>
#include <pxr/usd/usd/primRange.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usdGeom/bboxCache.h>
#include "pxr/usd/usdGeom/camera.h"
#include "pxr/usd/usdGeom/metrics.h"
#include <pxr/imaging/hgiMetal/hgi.h>
#include <pxr/imaging/hgiMetal/texture.h>
#include <pxr/imaging/hdx/types.h>
#include <pxr/imaging/hgi/blitCmdsOps.h>
#include <pxr/usdImaging/usdImagingGL/engine.h>

#include <pxr/imaging/hdx/tokens.h>

#import <CoreImage/CIContext.h>
#import <MetalKit/MetalKit.h>

#include <cmath>
#include <mutex>
#include <string>
#include <vector>

using namespace pxr;

static const MTLPixelFormat AAPLDefaultColorPixelFormat = MTLPixelFormatBGRA8Unorm;
static const double AAPLDefaultFocalLength = 18.0;
static const uint32_t AAPLMaxBuffersInFlight = 3;

/// Returns the current time in seconds from the system high-resolution clock.
static inline double getCurrentTimeInSeconds() {
    using Clock = std::chrono::high_resolution_clock;
    using Ns = std::chrono::nanoseconds;
    std::chrono::time_point<Clock, Ns> tp = std::chrono::high_resolution_clock::now();
    return tp.time_since_epoch().count() / 1e9;
}

/// Returns true if the bounding box has infinite floating point values.
bool isInfiniteBBox(const GfBBox3d &bbox) {
    return (isinf(bbox.GetRange().GetMin().GetLength()) ||
            isinf(bbox.GetRange().GetMax().GetLength()));
}

/// Creates a light source located at the camera position.
GlfSimpleLight computeCameraLight(const GfMatrix4d &cameraTransform) {
    GfVec3f cameraPosition = GfVec3f(cameraTransform.ExtractTranslation());

    GlfSimpleLight light;
    light.SetPosition(GfVec4f(cameraPosition[0], cameraPosition[1], cameraPosition[2], 1));

    return light;
}

/// Computes all light sources for the scene.
GlfSimpleLightVector computeLights(const GfMatrix4d &cameraTransform) {
    GlfSimpleLightVector lights;
    lights.push_back(computeCameraLight(cameraTransform));

    return lights;
}

/// Checks if the USD prim derives from the requested schema type.
bool primDerivesFromSchemaType(UsdPrim const &prim, TfType const &schemaType) {
    // Check if the schema `TfType` is defined.
    if (schemaType.IsUnknown()) {
        return false;
    }

    // Get the primitive `TfType` string to query the USD plugin registry instance.
    const std::string &typeName = prim.GetTypeName().GetString();

    // Return `true` if the prim's schema type is found in the plugin registry.
    return !typeName.empty() &&
            PlugRegistry::GetInstance().FindDerivedTypeByName<UsdSchemaBase>(typeName).IsA(schemaType);
}

/// Queries the USD for all the prims that derive from the requested schema type.
std::vector<UsdPrim> getAllPrimsOfType(UsdStagePtr const &stage,
        TfType const &schemaType) {
    std::vector<UsdPrim> result;
    UsdPrimRange range = stage->Traverse();
    std::copy_if(range.begin(), range.end(), std::back_inserter(result),
            [schemaType](UsdPrim const &prim) {
                return primDerivesFromSchemaType(prim, schemaType);
            });
    return result;
}

/// Computes a frustum from the camera and the current view size.
GfFrustum computeFrustum(const GfMatrix4d &cameraTransform,
        CGSize viewSize,
        const AAPLCameraParams &cameraParams) {
    GfCamera camera;
    camera.SetTransform(cameraTransform);
    GfFrustum frustum = camera.GetFrustum();
    camera.SetFocalLength(cameraParams.focalLength);

    if (cameraParams.projection == Perspective) {
        double targetAspect = double(viewSize.width) / double(viewSize.height);
        float filmbackWidthMM = 24.0;
        double hFOVInRadians = 2.0 * atan(0.5 * filmbackWidthMM / cameraParams.focalLength);
        double fov = (180.0 * hFOVInRadians) / M_PI;
        frustum.SetPerspective(fov, targetAspect, 1.0, 100000.0);
    } else {
        double left = cameraParams.leftBottomNear[0] * cameraParams.scaleViewport;
        double right = cameraParams.rightTopFar[0] * cameraParams.scaleViewport;
        double bottom = cameraParams.leftBottomNear[1] * cameraParams.scaleViewport;
        double top = cameraParams.rightTopFar[1] * cameraParams.scaleViewport;
        double nearPlane = cameraParams.leftBottomNear[2];
        double farPlane = cameraParams.rightTopFar[2];

        frustum.SetOrthographic(left, right, bottom, top, nearPlane, farPlane);
    }

    return frustum;
}

/// Creates a Hydra Storm renderer and uses it to render to a Metal texture.
@implementation AAPLRenderer {
    id <MTLDevice> _device;
    id <MTLRenderPipelineState> _blitToViewPSO;
    dispatch_semaphore_t _inFlightSemaphore;

    double _startTimeInSeconds;
    double _timeCodesPerSecond;
    double _startTimeCode;
    double _endTimeCode;
    GfVec3d _worldCenter;
    double _worldSize;
    int32_t _requestedFrames;
    bool _sceneSetup;

    GlfSimpleMaterial _material;
    GfVec4f _sceneAmbient;

    HgiUniquePtr _hgi;
    std::shared_ptr<class UsdImagingGLEngine> _engine;
    UsdStageRefPtr _stage;
}

/// Sets an initial material for the scene.
- (void)initializeMaterial {
    float kA = 0.2f;
    float kS = 0.1f;
    _material.SetAmbient(GfVec4f(kA, kA, kA, 1.0f));
    _material.SetSpecular(GfVec4f(kS, kS, kS, 1.0f));
    _material.SetShininess(32.0);

    _sceneAmbient = GfVec4f(0.01f, 0.01f, 0.01f, 1.0f);
}

/// Initializes the view.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view {
    if (self = [super init]) {
        _device = MTLCreateSystemDefaultDevice();;
        view.device = _device;
        view.colorPixelFormat = AAPLDefaultColorPixelFormat;
        view.sampleCount = 1;
        view.layer.backgroundColor = [NSColor clearColor].CGColor;
        view.layer.opaque = false;
        _requestedFrames = 1;
        _startTimeInSeconds = 0;
        _sceneSetup = false;

        [self loadMetal];
        [self initializeMaterial];
    }

    return self;
}

/// Frees the memory for the engine and stage.
- (void)dealloc {
    _engine.reset();
    _stage.Reset();
    _device = nil;
}

/// Prepares the Metal objects for copying to the view.
- (void)loadMetal {
    NSError *error = NULL;
    id <MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vtxBlit"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragBlitLinear"];

    // Set up the pipeline state object.
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.rasterSampleCount = 1;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatInvalid;

    // Configure the color attachment for blending.
    MTLRenderPipelineColorAttachmentDescriptor *colorDescriptor = pipelineStateDescriptor.colorAttachments[0];
    colorDescriptor.pixelFormat = AAPLDefaultColorPixelFormat;
    colorDescriptor.blendingEnabled = YES;
    colorDescriptor.rgbBlendOperation = MTLBlendOperationAdd;
    colorDescriptor.alphaBlendOperation = MTLBlendOperationAdd;
    colorDescriptor.sourceRGBBlendFactor = MTLBlendFactorOne;
    colorDescriptor.sourceAlphaBlendFactor = MTLBlendFactorOne;
    colorDescriptor.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    colorDescriptor.destinationAlphaBlendFactor = MTLBlendFactorZero;

    _blitToViewPSO = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_blitToViewPSO) {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
}

/// Copies the texture to the view with a shader.
- (void)blitToView:(nonnull MTKView *)view
     commandBuffer:(nonnull id <MTLCommandBuffer>)commandBuffer
           texture:(nonnull id <MTLTexture>)texture {
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (!renderPassDescriptor)
        return;

    // Create a render command encoder to encode copy command.
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (!renderEncoder)
        return;

    // Blit the texture to the view.
    [renderEncoder pushDebugGroup:@"FinalBlit"];
    [renderEncoder setFragmentTexture:texture atIndex:0];
    [renderEncoder setRenderPipelineState:_blitToViewPSO];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [renderEncoder popDebugGroup];

    // Finish encoding the copy command.
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
}

/// Requests the bounding box cache from Hydra.
- (UsdGeomBBoxCache)computeBboxCache {
    TfTokenVector purposes;
    purposes.push_back(UsdGeomTokens->default_);
    purposes.push_back(UsdGeomTokens->proxy);

    // Extent hints are sometimes authored as an optimization to avoid
    // computing bounds. They are particularly useful for some tests where
    // there's no bound on the first frame.
    bool useExtentHints = true;
    UsdTimeCode timeCode = UsdTimeCode::Default();
    if (_stage->HasAuthoredTimeCodeRange()) {
        timeCode = _stage->GetStartTimeCode();
    }
    UsdGeomBBoxCache bboxCache(timeCode, purposes, useExtentHints);
    return bboxCache;
}

/// Uses Hydra to load the USD or USDZ file.
- (bool)loadStage:(NSString *)filePath {
    _stage = UsdStage::Open([filePath UTF8String]);
    if (!_stage) {
        NSLog(@"Failed to load stage at %@", filePath);
        return false;
    }
    return true;
}

/// Initializes the Storm engine.
- (void)initializeEngine {
    _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);

    SdfPathVector excludedPaths;
    _hgi = Hgi::CreatePlatformDefaultHgi();
    HdDriver driver{HgiTokens->renderDriver, VtValue(_hgi.get())};

    _engine.reset(new UsdImagingGLEngine(_stage->GetPseudoRoot().GetPath(),
            excludedPaths, SdfPathVector(),
            SdfPath::AbsoluteRootPath(), driver));

    _engine->SetEnablePresentation(false);
    _engine->SetRendererAov(HdAovTokens->color);

    return;
}

/// Draws the scene using Hydra.
- (HgiTextureHandle)drawWithHydraAt:(double)timeCode
                           viewSize:(CGSize)viewSize {
    // Camera projection setup.
    GfMatrix4d cameraTransform = [_viewCamera getTransform];
    AAPLCameraParams cameraParams = [_viewCamera getShaderParams];
    GfFrustum frustum = computeFrustum(cameraTransform, viewSize, cameraParams);
    GfMatrix4d modelViewMatrix = frustum.ComputeViewMatrix();
    GfMatrix4d projMatrix = frustum.ComputeProjectionMatrix();
    _engine->SetCameraState(modelViewMatrix, projMatrix);

    // Viewport setup.
    GfVec4d viewport(0, 0, viewSize.width, viewSize.height);
    _engine->SetRenderViewport(viewport);
    _engine->SetWindowPolicy(CameraUtilMatchVertically);

    // Light and material setup.
    GlfSimpleLightVector lights = computeLights(cameraTransform);
    _engine->SetLightingState(lights, _material, _sceneAmbient);

    // Nondefault render parameters.
    UsdImagingGLRenderParams params;
    params.clearColor = GfVec4f(0.0f, 0.0f, 0.0f, 0.0f);
    params.colorCorrectionMode = HdxColorCorrectionTokens->sRGB;
    params.frame = timeCode;

    // Render the frame.
    TfErrorMark mark;
    _engine->Render(_stage->GetPseudoRoot(), params);
    TF_VERIFY(mark.IsClean(), "Errors occurred while rendering!");

    // Return the color output.
    return _engine->GetAovTexture(HdAovTokens->color);
}

/// Draw the scene, and blit the result to the view.
/// Returns false if the engine wasn't initialized.
- (bool)drawMainView:(MTKView *)view timeCode:(double)timeCode {
    if (!_engine) {
        return false;
    }

    // Start the next frame.
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    HgiMetal *hgi = static_cast<HgiMetal *>(_hgi.get());
    hgi->StartFrame();

    // Draw the scene using Hydra, and recast the result to a MTLTexture.
    CGSize viewSize = [view drawableSize];
    HgiTextureHandle hgiTexture = [self drawWithHydraAt:timeCode viewSize:viewSize];
    id <MTLTexture> texture = static_cast<HgiMetalTexture *>(hgiTexture.Get())->GetTextureId();

    // Create a command buffer to blit the texture to the view.
    id <MTLCommandBuffer> commandBuffer = hgi->GetPrimaryCommandBuffer();
    __block dispatch_semaphore_t blockSemaphore = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id <MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(blockSemaphore);
    }];

    // Copy the rendered texture to the view.
    [self blitToView:view commandBuffer:commandBuffer texture:texture];

    // Tell Hydra to commit the command buffer, and complete the work.
    hgi->CommitPrimaryCommandBuffer();
    hgi->EndFrame();

    return true;
}

/// Increases a counter that the draw method uses to determine if a frame needs to be rendered.
- (void)requestFrame {
    _requestedFrames++;
}

/// Loads the scene from the provided URL and prepares the camera.
- (void)setupScene:(nonnull NSString *)url {
    // Load USD stage.
    if (![self loadStage:url]) {
        // Failed to load stage. Nothing to render.
        return;
    }

    // Get scene information.
    [self getSceneInformation];

    // Set up the initial scene camera based on the loaded stage.
    [self setupCamera];

    _sceneSetup = true;
}

/// Determine the size of the world so the camera will frame its entire bounding box.
- (void)calculateWorldCenterAndSize {
    UsdGeomBBoxCache bboxCache = [self computeBboxCache];

    GfBBox3d bbox = bboxCache.ComputeWorldBound(_stage->GetPseudoRoot());

    // Copy the behavior of usdView.
    // If the bounding box is empty or infinite, set it to a default size.
    if (bbox.GetRange().IsEmpty() || isInfiniteBBox(bbox)) {
        bbox = {{{-10, -10, -10}, {10, 10, 10}}};
    }

    GfRange3d world = bbox.ComputeAlignedRange();

    _worldCenter = (world.GetMin() + world.GetMax()) / 2.0;
    _worldSize = world.GetSize().GetLength();
}

/// Sets a camera up so that it sees the entire scene.
- (void)setupCamera {
    [self calculateWorldCenterAndSize];

    std::vector<UsdPrim> sceneCameras = getAllPrimsOfType(_stage, TfType::Find<UsdGeomCamera>());

    if (sceneCameras.empty()) {
        _viewCamera = [[AAPLCamera alloc] initWithRenderer:self];
        [_viewCamera setRotation:{0.0, 0.0, 0.0}];
        [_viewCamera setFocus:_worldCenter];
        [_viewCamera setDistance:_worldSize];

        if (_worldSize <= 16.0) {
            [_viewCamera setScaleBias:1.0];
        } else {
            [_viewCamera setScaleBias:std::log(_worldSize / 16.0 * 1.8) / std::log(1.8)];
        }

        [_viewCamera setFocalLength:AAPLDefaultFocalLength];
        [_viewCamera setStandardFocalLength:AAPLDefaultFocalLength];
    } else {
        UsdPrim sceneCamera = sceneCameras[0];
        UsdGeomCamera geomCamera = UsdGeomCamera(sceneCamera);
        GfCamera camera = geomCamera.GetCamera(_startTimeCode);
        _viewCamera = [[AAPLCamera alloc] initWithSceneCamera:camera renderer:self];
    }
}

/// Gets important information about the scene, such as frames per second and if the z-axis points up.
- (void)getSceneInformation {
    _timeCodesPerSecond = _stage->GetFramesPerSecond();
    if (_stage->HasAuthoredTimeCodeRange()) {
        _startTimeCode = _stage->GetStartTimeCode();
        _endTimeCode = _stage->GetEndTimeCode();
    }
    _isZUp = (UsdGeomGetStageUpAxis(_stage) == UsdGeomTokens->z);
}

/// Updates the animation timing variables.
- (double)updateTime {
    double currentTimeInSeconds = getCurrentTimeInSeconds();

    // Store the ticks for the first frame.
    if (_startTimeInSeconds == 0) {
        _startTimeInSeconds = currentTimeInSeconds;
    }

    // Calculate the elapsed time in seconds from the start.
    double elapsedTimeInSeconds = currentTimeInSeconds - _startTimeInSeconds;

    // Loop the animation if it is past the end.
    double timeCode = _startTimeCode + elapsedTimeInSeconds * _timeCodesPerSecond;
    if (timeCode > _endTimeCode) {
        timeCode = _startTimeCode;
        _startTimeInSeconds = currentTimeInSeconds;
    }

    return timeCode;
}

/// Draws the scene into the view if there's a scene to render.
- (void)drawInMTKView:(MTKView *)view {
    // There's nothing to render until the scene is set up.
    if (!_sceneSetup) {
        return;
    }

    // There's nothing to render if there isn't a frame requested or the stage isn't animated.
    if (_requestedFrames == 0 && _startTimeCode == _endTimeCode) {
        return;
    }

    // Set up the engine the first time you attempt to render the stage.
    if (!_engine) {
        // Initialize the Storm render engine.
        [self initializeEngine];
    }

    double timeCode = [self updateTime];

    bool drawSucceeded = [self drawMainView:view
                                   timeCode:timeCode];

    if (drawSucceeded) {
        _requestedFrames--;
    }
}

/// Called during a resize event and requests a new frame to draw.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    [self requestFrame];
}

- (void)panByDelta:(float)deltaX
                  :(float)deltaY {
    [self.viewCamera panByDelta: pxr::GfVec2d(deltaX, deltaY)];
}

- (void)rotateByDelta:(float)deltaX
                     :(float)deltaY {
    [self.viewCamera rotateByDelta: pxr::GfVec2d(deltaX, deltaY)];
}

- (void)zoomByDelta:(float)delta {
    [self.viewCamera zoomByDelta: delta];
}

@end

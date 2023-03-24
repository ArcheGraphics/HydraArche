//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

#import "Camera.h"
#import "Renderer.h"

#include <pxr/base/gf/frustum.h>

static double const _minFocalLength = 10.0;
static double const _maxFocalLength = 500.0;

using namespace pxr;

@implementation AAPLCamera {
    AAPLRenderer *_renderer;
}

/// Copies the class to a new instance.
- (nonnull id)mutableCopyWithZone:(nullable NSZone *)zone {
    AAPLCamera *copy = [[AAPLCamera allocWithZone:zone] initWithRenderer:_renderer];

    if (copy) {
        copy.position = self.position;
        copy.focus = self.focus;
        copy.rotation = self.rotation;
        copy.distance = self.distance;
        copy.focalLength = self.focalLength;
        copy.standardFocalLength = self.standardFocalLength;
        copy.scaleBias = self.scaleBias;
        copy.projection = self.projection;
        copy.leftBottomNear = self.leftBottomNear;
        copy.rightTopFar = self.rightTopFar;
        copy.scaleViewport = self.scaleViewport;
    }

    return copy;
}

/// Initializes the class and sets the current renderer.
- (nullable id)initWithRenderer:(nonnull AAPLRenderer *)renderer {
    self = [super init];
    if (self) {
        _renderer = renderer;
        self.rotation = pxr::GfVec3d(0.0);
        self.focus = pxr::GfVec3d(0.0);
        self.distance = 50.0;
        self.scaleViewport = 1.0;
    }

    return self;
}

/// Initializes a camera instance and sets the camera configuration and the current renderer.
- (nullable id)initWithSceneCamera:(const GfCamera &)sceneCamera
                          renderer:(nonnull AAPLRenderer *)renderer {
    self = [super init];
    if (self) {
        GfMatrix4d cameraTransform(1.0);
        cameraTransform = sceneCamera.GetTransform();

        if (renderer.isZUp) {
            cameraTransform = cameraTransform * GfMatrix4d().SetRotate(
                    GfRotation(GfVec3d::XAxis(), -90.0));
        }

        GfVec3d rotation = cameraTransform.DecomposeRotation(
                GfVec3d::YAxis(),
                GfVec3d::XAxis(),
                GfVec3d::ZAxis());

        self.rotation = {rotation[1], rotation[0], rotation[2]};

        const GfFrustum frustum = sceneCamera.GetFrustum();
        const GfVec3d position = frustum.GetPosition();
        const GfVec3d viewDir = frustum.ComputeViewDirection();

        self.distance = sceneCamera.GetFocusDistance();
        self.focus = position + self.distance * viewDir;
        self.focalLength = sceneCamera.GetFocalLength();

        _renderer = renderer;
    }

    return self;
}

/// Composes a final rotation matrix and adjusts if the scene z-axis is up.
- (void)setPositionFromFocus {
    GfRotation gfRotation = [self getRotation];
    GfVec3d viewDir = gfRotation.TransformDir(-GfVec3d::ZAxis());
    self.position = self.focus - self.distance * viewDir;
}

/// Moves the camera by the specified delta and requests a new frame to render.
- (void)panByDelta:(pxr::GfVec2d)delta {
    GfRotation gfRotation = [self getRotation];
    GfMatrix4d cameraTransform = GfMatrix4d().SetRotate(gfRotation.GetInverse());

    GfVec4d xColumn = cameraTransform.GetColumn(0);
    GfVec4d yColumn = cameraTransform.GetColumn(1);

    GfVec3d xAxis(xColumn[0], xColumn[1], xColumn[2]);
    GfVec3d yAxis(yColumn[0], yColumn[1], yColumn[2]);
    double scale = _scaleBias * std::abs(_distance / 256.0);

    _focus += scale * (delta[0] * xAxis + delta[1] * yAxis);

    [_renderer requestFrame];
}

/// Adjusts the X and Y rotations and requests a new frame to render.
- (void)rotateByDelta:(pxr::GfVec2d)delta {
    self.rotation += {delta[1], delta[0], 0.0f};
    [_renderer requestFrame];
}

/// Adjusts the current zoom and requests a new frame to render.
- (void)zoomByDelta:(double)delta {
    if (self.projection == Orthographic) {
        self.scaleViewport += 0.1 * ((delta > 0) - (delta < 0));
        self.scaleViewport = std::max(0.1, self.scaleViewport);
    } else {
        self.distance += delta * self.scaleBias;
    }

    [_renderer requestFrame];
}

/// Sets the new zoom and requests a new frame to render.
- (void)setZoomFactor:(double)zoomFactor {
    _focalLength = _standardFocalLength * zoomFactor;
    [_renderer requestFrame];
}

/// Gets the zoom factor based on the focal length.
- (double)getZoomFactor {
    return _focalLength / _standardFocalLength;
}

/// Composes a final rotation matrix and adjusts if the scene z-axis is up.
- (pxr::GfRotation)getRotation {
    GfRotation gfRotation = GfRotation(GfVec3d::ZAxis(), _rotation[2]) *
            GfRotation(GfVec3d::XAxis(), _rotation[0]) *
            GfRotation(GfVec3d::YAxis(), _rotation[1]);

    if (_renderer.isZUp) {
        gfRotation = gfRotation * GfRotation(GfVec3d::XAxis(), 90.0);
    }

    return gfRotation;
}

/// Composes the final matrix for the camera.
- (pxr::GfMatrix4d)getTransform {
    GfRotation gfRotation = [self getRotation];
    GfMatrix4d cameraTransform(1.0);

    cameraTransform =
            GfMatrix4d().SetTranslate(GfVec3d(0.0, 0.0, _distance)) *
                    GfMatrix4d().SetRotate(gfRotation) *
                    GfMatrix4d().SetTranslate(_focus);

    return cameraTransform;
}

/// Builds the data structure for the camera shader parameters.
- (AAPLCameraParams)getShaderParams {
    AAPLCameraParams shaderParams{_rotation,
            _focus,
            _distance,
            _focalLength,
            _projection,
            _leftBottomNear,
            _rightTopFar,
            _scaleViewport};

    return shaderParams;
}

@end

//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

#pragma once

#import <Foundation/Foundation.h>

#include <pxr/base/gf/vec2d.h>
#include <pxr/base/gf/vec3d.h>
#include <pxr/base/gf/camera.h>
#include <pxr/base/gf/matrix4d.h>
#include <pxr/base/gf/rotation.h>

typedef NS_ENUM(NSUInteger, Projection) {
    Perspective = 0,
    Orthographic
};

typedef struct {
    pxr::GfVec3d rotation;
    pxr::GfVec3d focus;
    double distance;
    double focalLength;
    Projection projection;
    pxr::GfVec3d leftBottomNear;
    pxr::GfVec3d rightTopFar;
    double scaleViewport;
} AAPLCameraParams;

@class AAPLRenderer;

@interface AAPLCamera : NSObject <NSMutableCopying>

/// Copies the class to a new instance.
- (nonnull id)mutableCopyWithZone:(nullable NSZone *)zone;

/// Initializes the class and sets the current renderer.
- (nullable id)initWithRenderer:(nonnull AAPLRenderer *)renderer;

/// Initializes a camera instance and sets the camera configuration and the current renderer.
- (nullable id)initWithSceneCamera:(const pxr::GfCamera &)sceneCamera
                          renderer:(nonnull AAPLRenderer *)renderer;

/// Sets the camera position based on the current focus.
- (void)setPositionFromFocus;

/// Moves the camera by the specified delta and requests a new frame to render.
- (void)panByDelta:(pxr::GfVec2d)delta;

/// Adjusts the x- and y-rotations and requests a new frame to render.
- (void)rotateByDelta:(pxr::GfVec2d)delta;

/// Adjusts the current zoom and requests a new frame to render.
- (void)zoomByDelta:(double)delta;

/// Sets the new zoom and requests a new frame to render.
- (void)setZoomFactor:(double)zoomFactor;

/// Gets the zoom factor based on the focal length.
- (double)getZoomFactor;

/// Compose a final rotation matrix and adjusts if the scene Z axis is up.
- (pxr::GfRotation)getRotation;

/// Composes the final matrix for the camera.
- (pxr::GfMatrix4d)getTransform;

/// Builds the data structure for the camera shader parameters.
- (AAPLCameraParams)getShaderParams;

@property(nonatomic) pxr::GfVec3d position;
@property(nonatomic) pxr::GfVec3d rotation;
@property(nonatomic) pxr::GfVec3d focus;
@property(nonatomic) double distance;
@property(nonatomic) double focalLength;
@property(nonatomic) double standardFocalLength;
@property(nonatomic) double scaleBias;
@property(nonatomic) Projection projection;
@property(nonatomic) pxr::GfVec3d leftBottomNear;
@property(nonatomic) pxr::GfVec3d rightTopFar;
@property(nonatomic) double scaleViewport;

@end

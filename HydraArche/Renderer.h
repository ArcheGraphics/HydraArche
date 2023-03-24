//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

#pragma once

#import <MetalKit/MetalKit.h>

@class AAPLCamera;

@interface AAPLRenderer : NSObject <MTKViewDelegate>

/// Initializes the view.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;

/// Loads the scene from the provided URL and prepares the camera.
- (void)setupScene:(nonnull NSString *)url;

/// Informs the draw method that a frame needs to be rendered.
- (void)requestFrame;

@property(nonatomic) bool isZUp;

@property(nonnull, nonatomic) AAPLCamera *viewCamera;

@end

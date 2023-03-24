# HydraArche - Swift usd editor powered by Storm Hydra

## Motivation

ArcheGraphic is a graphics project developed based on USD. 
USD includes a rendering proxy framework Hydra, 
and Apple officially implemented a high-performance Metal backend to support Viewport's high-performance rendering. 
Therefore, the HydraArche project is based on this renderer, combined with SwiftUI to develop USD editor. 
The USD file exported by this editor will be used in SwiftArche's mobile engine (USD supports WIP)

In addition, since USD is written in C++ and lacks Swift bindings 
(Apple's official ModelI/O should also use USD internally but is not open source), 
this project will develop this binding library for USD Reading and writing of files. 
This binding library will also be used in the refactoring of the SwiftArche project.

## Cloning && Install

This repository contains submodules for external dependencies, so when doing a fresh clone you need to clone
recursively:

```
git clone --recursive https://github.com/ArcheGraphics/HydraArche.git
```

Existing repositories can be updated manually:

```
git submodule init
git submodule update
```

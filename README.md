Filmlog
==================

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Introduction
------------

Filmlog is a film photography companion app designed to help you organize your film rolls and frames with precision and ease. Add metadata like roll name, push/pull rating, and film stock; attach reference photos of your roll and light meter readings; and keep track of individual frames as you shoot.

Think like a film photographer — Filmlog encourages a traditional analogue mindset, with fixed rolls, manual exposure control, and deliberate framing. Whether you're shooting real film or using the app as a digital scouting tool, Filmlog helps you stay grounded in the discipline of film photography.

Designed with a photographic look and feel, Filmlog blends tactile analogue inspiration with modern iPhone controls. It's both a practical companion for traditional photography workflows and a creative tool for visual planning and exposure training.

Change log:

| Date       | Description                             |
|------------|-----------------------------------------|
| 2025-08-28 | Application in development |


Screenshots
------------



Documentation
------------


Technical Notes
-----------------

### Look development

The provided .cube LUT files were generated using the photographic-dctls project. This repository offers a set of DCTL-based tools for photographic color processing and creative look development.

Additionally, the Lut_powergrade.drx file contains a DaVinci Resolve PowerGrade used to design and export custom looks. This PowerGrade follows a consistent color workflow designed to ensure compatibility with both Metal rendering and sRGB MTKView output on iOS/macOS.

The color pipeline includes the following stages:

- Conversion from YCbCr to Rec.709
- Transform to Cineon log
- Print film emulation
- Custom curves and HSL adjustments
- Conversion back from Rec.709 gamma to linear RGB

The .cube LUTs are saved at a 33×33×33 resolution, offering a good balance between visual fidelity and fast loading performance in Metal.

* Photographic-dctls       
https://github.com/mikaelsundell/photographic-dctls

Known Limitations
-----------------

### Fixed Aperture (f/1.6)

The iPhone camera hardware uses a fixed aperture (e.g. f/1.6), meaning it's not possible to simulate different f-stops natively. On DSLR or mirrorless systems, camera manufacturers often raise the aperture number (e.g. f/16) and increase ISO, then reduce ISO to simulate different aperture values. This is not feasible on iPhone due to the hardware constraint.

To approximate the effects of aperture changes:
- We calculate the exposure delta compared to f/1.6.
- First, we adjust ISO to compensate.
- Second, if ISO boundaries are exceeded, we adjust the shutter speed — while also attempting to stay close to mains-compatible frequencies (e.g. 1/50s or 1/60s) to minimize flicker under non-studio lighting conditions.

As a result, this can introduce flickering under non-studio lighting conditions, especially when the adjusted shutter speeds conflict with local mains frequencies (e.g. 50Hz or 60Hz), leading to visible pulsing or flicker in the image.

### Uncontrollable ISP Exposure Adjustments

The iPhone’s **Image Signal Processor (ISP)** performs automatic tone mapping and temporal noise reduction — even when exposure is manually locked. This results in:
- Minor but noticeable fluctuations in brightness over time.
- Minor “auto exposure” behavior even under manual control.

> Keeping the phone still, or using fixed scenes with stable lighting, helps minimize this effect.

### YCbCr to sRGB custom Metal pipeline and AVCaptureVideoPreviewLayer

The estimated exposure value (EV) from the custom Metal pipeline differs by approximately 3 stops compared to AVCaptureVideoPreviewLayer. This discrepancy is likely due to differences in pixel formats or tone mapping. While this offset is compensated for in EV exposure mode, the underlying cause remains technically unresolved.

* Apple Developer Forum
https://developer.apple.com/forums/thread/795593

Documentation
-------
* Metal Feature Set Tables          
https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf


Project
-------
* GitHub page   
https://github.com/mikaelsundell/filmlog

* Issues   
https://github.com/mikaelsundell/filmlog/issues

Copyright
---------

App icon:
<a href="https://www.flaticon.com/free-icons/optics" title="optics icons">Optics icons created by meaicon - Flaticon</a>

-------
README crafted with a little help from ChatGPT
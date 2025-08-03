Filmlog
==================

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Introduction
------------
Filmlog is a film photography companion app that helps you organize your film rolls and frames. Add metadata like roll name, push/pull rating, and film stock, attach photos of the roll and light meter readings, and track individual frames.


Preview
------------



Documentation
------------



Known Limitations
-----------------

### 1. Fixed Aperture (f/1.6)

The iPhone camera hardware uses a **fixed aperture** (e.g. f/1.6), meaning it's not possible to simulate different f-stops natively. On DSLR or mirrorless systems, camera manufacturers often raise the aperture number (e.g. f/16) and increase ISO, then reduce ISO to simulate different aperture values. This is not feasible on iPhone due to the hardware constraint.

To approximate the effects of aperture changes:
- We calculate the exposure delta compared to f/1.6.
- **First**, we adjust ISO to compensate.
- **Second**, if ISO boundaries are exceeded, we adjust the shutter speed.

> For low ISO film stocks, flickering may still occur due to the need to use non-Hz-compatible shutter speeds.

### 2. Uncontrollable ISP Exposure Adjustments

The iPhone’s **Image Signal Processor (ISP)** performs automatic tone mapping and temporal noise reduction — even when exposure is manually locked. This results in:
- Minor but noticeable fluctuations in brightness over time.
- Minor “auto exposure” behavior even under manual control.

> Keeping the phone still, or using fixed scenes with stable lighting, helps minimize this effect.



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

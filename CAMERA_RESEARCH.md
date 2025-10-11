# Camera Hardware Research for 60fps Race Timing

## Research Date: October 11, 2025

This document contains research on camera hardware options for achieving 60fps video recording on macOS for race timing applications.

---

## Current Limitation

**Apple Continuity Camera** (iPhone as webcam via wireless or USB):
- ❌ Limited to **30fps maximum**
- ❌ Does not support `activeFormat` API (preset-only)
- ❌ Both wireless and wired USB connections limited to 30fps
- ✅ Works for basic timing but lacks precision of 60fps

---

## Requirements

For optimal race timing system:
1. **60fps** minimum (preferably 120-240fps for slow-motion review)
2. **3x optical zoom** minimum (to frame finish line from distance)
3. **1080p resolution** minimum
4. **macOS compatible** (works with AVCaptureDevice/AVFoundation)
5. **USB connection** preferred for reliability

---

## Recommended Camera Options

### Option 1: PTZ Cameras (Pan-Tilt-Zoom) - Professional Grade

#### PTZOptics USB Cameras
- **Price**: $600-1200
- **Optical Zoom**: 20x
- **Frame Rate**: 1080p at 60fps
- **Connection**: USB (UVC compliant)
- **macOS Support**: Yes (works with AVCaptureDevice)
- **Features**:
  - Remote control for pan/tilt/zoom
  - Professional quality image
  - Excellent for fixed installation
  - Multiple models available (12x, 20x, 30x zoom)
- **Pros**:
  - Motorized zoom control
  - Excellent zoom range
  - Professional reliability
  - Remote controllable
- **Cons**:
  - Higher cost
  - May be overkill for simple timing
- **Best For**: Professional setups, multiple race courses, adjustable positioning

#### AVer CAM520
- **Price**: ~$800
- **Optical Zoom**: 12x
- **Frame Rate**: 1080p at 60fps
- **Connection**: USB plug-and-play
- **macOS Support**: Yes
- **Features**:
  - Excellent image quality
  - Remote control included
  - Professional grade
- **Pros**:
  - Outstanding image quality
  - Reliable performance
  - Easy setup
- **Cons**:
  - Premium pricing
- **Best For**: High-quality professional installations

#### Logitech PTZ Pro 2
- **Price**: ~$900
- **Optical Zoom**: 10x
- **Frame Rate**: ❌ 1080p at 30fps only (NOT 60fps)
- **Connection**: USB
- **macOS Support**: Yes
- **Note**: Does NOT meet 60fps requirement - included for reference only

---

### Option 2: Manual Zoom USB Cameras - Budget Friendly

#### IEights 10x Varifocal USB Camera
- **Price**: $150-200
- **Optical Zoom**: 10x optical (5-50mm lens)
- **Frame Rate**: 1080p at 60fps (claims up to 260fps)
- **Connection**: USB
- **macOS Support**: Yes (UVC compliant)
- **Features**:
  - Manual zoom ring on lens
  - Budget-friendly
  - Some models claim 260fps capability
- **Pros**:
  - Very affordable
  - Good zoom range
  - High frame rate capability
  - Mac compatible
- **Cons**:
  - Manual zoom only (set once, not adjustable during recording)
  - Build quality may vary
  - Less professional appearance
- **Best For**: Budget setups, fixed zoom position
- **Amazon**: Search "IEights 260fps Variable Focus Camera"

#### IEights 4x Optical Zoom Camera
- **Price**: ~$120
- **Optical Zoom**: 4x optical (2.8-12mm)
- **Frame Rate**: 1080p at 60fps
- **Connection**: USB
- **macOS Support**: Yes
- **Features**:
  - Manual zoom
  - Budget option
- **Pros**:
  - Very affordable
  - Meets minimum 3x zoom requirement
  - 60fps capable
- **Cons**:
  - Limited zoom range
  - Manual zoom only
- **Best For**: Tight budget, minimum requirements

#### Elmo PX-10E Document Camera
- **Price**: ~$500
- **Optical Zoom**: 12x
- **Frame Rate**: 1080p at 60fps
- **Connection**: USB
- **Features**:
  - Designed for overhead viewing
  - Can be repositioned
- **Pros**:
  - Good zoom range
  - Reliable brand
- **Cons**:
  - Not designed for horizontal viewing (can be adapted)
  - Mid-range pricing
- **Best For**: Flexible positioning needs

---

### Option 3: High-End Webcams (60fps, No Optical Zoom)

These options provide 60fps but use **digital zoom** only - included for reference:

#### Elgato Facecam Pro
- **Price**: ~$300
- **Frame Rate**: 4K at 60fps
- **Zoom**: Digital only
- **macOS Support**: Yes
- ❌ No optical zoom

#### Logitech StreamCam
- **Price**: ~$170
- **Frame Rate**: 1080p at 60fps
- **Zoom**: Digital only
- **macOS Support**: Yes (10.14+)
- ❌ No optical zoom

#### Logitech Brio Ultra HD Pro
- **Price**: ~$200
- **Frame Rate**: 1080p at 60fps, 720p at 90fps
- **Zoom**: 5x digital zoom
- **macOS Support**: Yes (10.7+)
- ❌ No optical zoom

---

### Option 4: Action Cameras (Ultra High Frame Rates)

For **ultimate timing precision** with slow-motion review capability:

#### GoPro Hero 12/13
- **Price**: $300-500
- **Frame Rate**: Up to 240fps at 1080p
- **Zoom**: Digital zoom only
- **Connection**: Can work as USB webcam on macOS
- **Features**:
  - Super slow-motion capability
  - Excellent image stabilization
  - Waterproof/rugged
- **Pros**:
  - Frame-perfect timing with 240fps
  - Versatile usage
  - Professional quality
- **Cons**:
  - No optical zoom
  - More expensive
  - May require capture card for best quality
- **Best For**: Ultra-precise timing, slow-motion analysis
- ❌ No optical zoom

---

### Option 5: HDMI Cameras + Capture Card

For maximum flexibility:

#### Setup: Professional Camera + Elgato HD60 S+
- **Camera**: Any HDMI camera (DSLR, mirrorless, camcorder with optical zoom)
- **Capture Card**: Elgato HD60 S+ (~$200)
- **Frame Rate**: 1080p at 60fps
- **macOS Support**: Yes (appears as AVCaptureDevice)
- **Features**:
  - Use any camera with HDMI output
  - Maximum flexibility
  - Professional image quality
- **Pros**:
  - Best image quality possible
  - Can use existing cameras
  - Full manual control
  - Optical zoom on camera
- **Cons**:
  - More complex setup
  - Higher total cost
  - Requires HDMI cable management
- **Best For**: Existing camera owners, maximum quality needs

---

## Final Recommendations by Use Case

### Budget Setup (~$150-200)
**Recommended**: IEights 10x Varifocal Camera
- 10x optical zoom
- 1080p at 60fps
- Manual zoom (set once)
- Mac compatible
- **Best value for money**

### Professional Setup (~$800)
**Recommended**: AVer CAM520
- 12x optical zoom
- 1080p at 60fps
- Remote zoom control
- Excellent image quality
- **Best overall quality**

### Prosumer Setup (~$600-800)
**Recommended**: PTZOptics 20x USB Camera
- 20x optical zoom
- 1080p at 60fps
- Remote control
- Professional features
- **Best zoom range and control**

### Ultra-Precision Timing (Frame-Perfect)
**Recommended**: GoPro Hero 12 + Record natively
- 240fps capability
- Record on camera, transfer to Mac for processing
- Slow-motion review for exact frame
- **No optical zoom** - position camera closer

### Maximum Flexibility
**Recommended**: HDMI Capture Card + Existing Camera
- Use camcorder or mirrorless with optical zoom
- Elgato HD60 S+ capture card
- Professional image quality
- **Best for existing camera owners**

---

## Technical Compatibility Notes

### AVFoundation Support
- All USB UVC cameras work with `AVCaptureDevice` on macOS
- PTZ controls may require separate software/SDK
- Frame rate can be set via `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration`
- External cameras support custom format selection (unlike Continuity Camera)

### Recommended Workflow
1. Connect camera via USB
2. Camera appears in `AVCaptureDevice.DiscoverySession`
3. Query available formats via `device.formats`
4. Select format with 60fps support
5. Set `device.activeFormat` and frame duration
6. Record via `AVCaptureMovieFileOutput`

### Testing Note
All recommended cameras will work with the existing TimeKeeper code because they support:
- ✅ Direct format selection (`activeFormat`)
- ✅ Custom frame rate configuration
- ✅ AVCaptureDevice enumeration
- ✅ Standard H.264 encoding

---

## Professional Sports Timing Systems (Reference)

For comparison, professional race timing systems use specialized equipment:

### FinishLynx Photo-Finish Systems
- **Technology**: Line-scan cameras (not standard video)
- **Frame Rate**: 2,000-40,000 fps
- **Price**: $10,000+
- **Features**:
  - Sub-millisecond accuracy
  - Specialized for finish line
  - Industry standard for Olympics/professional racing
- **Note**: Completely different technology from standard video cameras

### ALGE OPTIc3
- **Technology**: Photo-finish line-scan
- **Frame Rate**: Highest available in line-scan mode
- **Price**: Professional pricing
- **Features**: Technical leader in photo-finish market

**These systems are referenced for context** - they represent the professional standard but are significantly more expensive than video-based solutions.

---

## Next Steps

1. **Test with available hardware**: Try app with Mac's built-in FaceTime camera to verify 60fps works with non-Continuity Camera devices
2. **Purchase decision**: Based on budget and needs, select appropriate camera
3. **Optional code enhancements**: Add PTZ control if using motorized camera
4. **Consider higher frame rates**: Modify code to support 120fps or 240fps if using capable camera

---

## References

- [PTZOptics USB Cameras](https://ptzoptics.com/usb/)
- [AVer CAM520 Product Page](https://presentation.aver.com/model/cam520)
- [IEights Cameras on Amazon](https://www.amazon.com/s?k=IEights+varifocal+camera)
- [Apple AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [FinishLynx Professional Timing Systems](https://finishlynx.com/)

---

## Document History

- Created: October 11, 2025
- Purpose: Camera hardware research for 60fps race timing application
- Application: TimeKeeper macOS app
- Author: Research compiled via Claude Code

# **Technical Project Analysis: iOS Gesture-Controlled Music Player**

## **1\. Project Overview & Core Architecture**

**Goal:** Engineering a high-performance iOS application utilizing the Vision framework to translate fine-motor hand gestures (Pinch & Extension) into real-time DSP (Digital Signal Processing) controls for audio playback.

**Core Tech Stack:**

* **Language:** Swift 5.9+ (Concurrency support required).  
* **UI Framework:** SwiftUI (MVVM Pattern).  
* **Computer Vision:** Vision (VN) \+ CoreML (underlying).  
* **Audio Engine:** AVFoundation (Local DSP), MediaPlayer (Apple Music), Spotify-iOS-SDK.  
* **Reactive Pipeline:** Combine (PassthroughSubjects for 60Hz gesture streams).

### **1.1 View Hierarchy & Navigation Architecture**

The app adopts a "Lens-First" architecture similar to social camera apps, utilizing a horizontal TabView with programmatic paging.

* **RootContainerView**: Holds the AppCoordinator state.  
  * **Left Page (SettingsView)**: Configuration for sensitivity, smoothing coefficients, and "No-Hands" debounce timing.  
  * **Center Page (ActiveSessionView)**: The primary viewport.  
    * *Layer 0 (Background):* CameraPreviewView (UIViewRepresentable wrapping AVCaptureVideoPreviewLayer).  
    * *Layer 1 (Overlay):* GestureCanvasView (High-performance SwiftUI Canvas using immediate mode drawing for \<16ms latency).  
    * *Layer 2 (HUD):* HeadsUpDisplay (Floating SwiftUI text confirming Pitch/Speed values).  
  * **Right Page (LibraryView)**: A unified media picker abstracting three data sources:  
    1. **Local/Imported:** UIDocumentPicker & PHPicker results.  
    2. **Apple Music:** MPMediaPickerController.  
    3. **Spotify:** OAuth flow & Playlist fetcher.

### **1.2 Info.plist & Privacy Compliance**

Strict permission handling is required for App Store approval.

\<key\>NSCameraUsageDescription\</key\>  
\<string\>Camera access is required to track hand coordinates for real-time audio control.\</string\>  
\<key\>NSAppleMusicUsageDescription\</key\>  
\<string\>Read access is required to load your music library for playback.\</string\>  
\<key\>NSMicrophoneUsageDescription\</key\>  
\<string\>Required for audio session routing, even if not recording voice.\</string\>  
\<key\>UIBackgroundModes\</key\>  
\<array\>  
    \<string\>audio\</string\>  
    \<string\>fetch\</string\>  
\</array\>

## **2\. The Computer Vision Pipeline**

### **2.1 Camera Session Architecture**

The standard AVCaptureSession must be tuned for CV (Computer Vision) to prevent thermal throttling while maintaining tracking accuracy.

* **Session Preset:** AVCaptureSession.Preset.high (1920x1080). 4K is unnecessary and increases CV latency.  
* **Pixel Format:** kCVPixelFormatType\_32BGRA. Vision works best with BGRA or 420YpCbCr8BiPlanarFullRange.  
* **Frame Rate:** Locked to 30 FPS or 60 FPS based on device thermal state. 60 FPS provides smoother audio control but higher battery drain.

### **2.2 Vision Request Optimization**

We utilize the VNDetectHumanHandPoseRequest.

* **Chirality Strategy:** We must explicitly track .leftHand vs .rightHand. Vision may flip chirality in complex lighting; we must implement a "temporal coherence" check (e.g., if a hand was "Right" 16ms ago, it is likely still "Right" unless it crossed the screen center).  
* **Point Extraction:**  
  * **Left Hand (Speed):** Track .thumbTip and .indexFingerTip.  
  * **Right Hand (Pitch):** Track .thumbTip and .indexFingerTip.  
  * **Volume:** Track .wrist (Left) and .wrist (Right).

## **3\. Advanced Signal Processing (The "Anti-Jitter" Layer)**

Raw Vision coordinates fluctuate due to lighting noise. Direct mapping to Audio Pitch results in audible "warbling." We implement a 1D Kalman Filter for each coordinate channel (x, y).

### **3.1 Mathematical Model**

For a coordinate ![][image1], we maintain a state estimate ![][image2] and error covariance ![][image3].

* **Process Noise (![][image4]):** Represents the user's actual hand tremor/movement.  
* **Measurement Noise (![][image5]):** Represents the camera/Vision inaccuracies.

**Swift Implementation Logic:**

class KalmanScalar {  
    private var x: Double \= 0.0 // State  
    private var p: Double \= 1.0 // Covariance  
    private let q: Double \= 0.005 // Process noise (Tuning param: Lower \= stiffer, Higher \= responsive)  
    private let r: Double \= 0.05  // Measurement noise (Tuning param: Higher \= smoother)  
      
    func update(\_ measurement: Double) \-\> Double {  
        // Predict  
        let p\_pred \= p \+ q  
          
        // Update  
        let kalman\_gain \= p\_pred / (p\_pred \+ r)  
        x \= x \+ kalman\_gain \* (measurement \- x)  
        p \= (1 \- kalman\_gain) \* p\_pred  
        return x  
    }  
}

### **3.2 Debounce & State Machine**

A standard Timer is insufficient for the "No Hands" pause logic due to dropped frames.

* **Logic:** Maintain a lastDetectedTimestamp.  
* **Update Loop:** In the game loop (DisplayLink), check CurrentTime \- lastDetectedTimestamp.  
* **Threshold:** If delta \> 1.0s, trigger .pause().  
* **Recovery:** Instant. If delta resets to 0, trigger .play() (only if it was auto-paused, not user-paused).

## **4\. The Hybrid Audio Engine**

iOS allows AVAudioEngine for raw data manipulation but restricts it for DRM content. We must engineer a **Strategy Pattern** wrapper.

### **4.1 Strategy Interface**

protocol AudioStrategy {  
    func play(track: AudioTrack)  
    func setSpeed(\_ speed: Float) // 0.5x to 2.0x  
    func setPitch(\_ pitch: Float) // \-2400 to \+2400 cents  
    func setVolume(\_ volume: Float) // 0.0 to 1.0  
}

### **4.2 Concrete Strategy A: Local DSP (Imported Files)**

Uses AVAudioEngine graph: Player \-\> TimePitch \-\> Mixer \-\> Output.

* **Pitch Shifting:** AVAudioUnitTimePitch.pitch. Measured in cents.  
  * Formula: ![][image6].  
* **Time Stretching:** AVAudioUnitTimePitch.rate.  
  * Range: ![][image7] to ![][image8]. We clamp this to ![][image9] \- ![][image10] for usability.

### **4.3 Concrete Strategy B: Apple Music (MPMedia)**

Uses MPMusicPlayerController.applicationMusicPlayer.

* **Limitations:** No Pitch/Speed control API.  
* **Fallback:** UI must disable Pitch/Speed gesture indicators (gray them out).  
* **Volume:** Controlled via MPVolumeView overlay or Application Music Player volume.

### **4.4 Concrete Strategy C: Spotify (App Remote)**

Uses SPTAppRemote via the Spotify application.

* **Connection:** Requires deep-linking to the main Spotify app to authorize.  
* **Limitations:** Latency is higher than local playback. No Pitch/Speed.

## **5\. File Import System**

### **5.1 Video Extraction (AVAssetExportSession)**

Users often have music in screen recordings.

1. **Input:** PHPickerViewController (Video filter).  
2. **Processing:** Load AVURLAsset.  
3. **Export:** Create AVAssetExportSession with AVAssetExportPresetAppleM4A.  
4. **Output:** Write .m4a to the app's FileManager.documentDirectory.

### **5.2 Security Scoped Resources**

When importing from UIDocumentPicker (iCloud Drive/Files):

* **Requirement:** You cannot pass the URL directly to AVAudioFile.  
* **Process:** 1\. url.startAccessingSecurityScopedResource()  
  2\. FileManager.copyItem(at: url, to: localDest)  
  3\. url.stopAccessingSecurityScopedResource()  
  4\. Play from localDest.

## **6\. Gesture Mathematics**

### **6.1 Normalized to Screen Space**

Vision returns points in a Normalized coordinate system (Bottom-Left 0,0 to Top-Right 1,1).

* **Conversion:** \* ![][image11]  
  * ![][image12] (Vision Y is inverted relative to UIKit).

### **6.2 Relative Pinch Scaling**

We use a **Relative Clutch** system, not absolute distance mapping.

1. **State:** isPinching (Bool), startPinchDist (Float), startParamValue (Float).  
2. **Event:** When dist(Thumb, Index) \< Threshold:  
   * If \!isPinching: Set isPinching \= true, Record startPinchDist.  
3. **Update:** While isPinching:  
   * ![][image13]  
   * ![][image14]  
   * Clamp ![][image15] to min/max limits.  
4. **Release:** When dist \> Threshold:  
   * Set isPinching \= false.

This allows the user to "grab" the setting and adjust it, rather than having the setting jump around wildly based on hand size.

## **7\. Performance & Thermal Gating**

Continuous Computer Vision \+ Audio DSP is computationally expensive.

* **Thermal State Monitoring:** Subscribe to ProcessInfo.processInfo.thermalStateDidChangeNotification.  
* **Mitigation Strategy:**  
  * *Nominal/Fair:* Run Vision at 60 FPS, High accuracy.  
  * *Serious:* Throttle Vision to 30 FPS.  
  * *Critical:* Disable Pitch/Speed shifting (bypass AVAudioUnitTimePitch), leaving only Volume control, to save CPU cycles.

## **8\. Detailed Implementation Task System**

*The following tasks are structured for sequential execution by an AI agent or developer team.*

### **Phase 1: Foundation & Infrastructure**

**Task 1.1: Project Scaffold & Permissions**

Initialize the Xcode project utilizing the SwiftUI App lifecycle. Immediately configure Info.plist to include NSCameraUsageDescription (tracking), NSAppleMusicUsageDescription (library access), and NSPhotoLibraryUsageDescription (video-import). Create the root ContentView containing a TabView with PageTabViewStyle. Create three placeholder views: SettingsView, ActiveSessionView, and LibraryView. Ensure the app compiles and requests camera permissions upon the first launch.

**Task 1.2: Camera Capture Service**

Create a CameraManager class inheriting from NSObject and ObservableObject. Configure an AVCaptureSession with .high preset. Attach AVCaptureDeviceInput for the front wide-angle camera. Attach AVCaptureVideoDataOutput, setting pixel format to kCVPixelFormatType\_32BGRA and its delegate to self on a background queue. Implement captureOutput to extract CMSampleBuffer and publish it via a Combine PassthroughSubject\<CVPixelBuffer, Never\>.

### **Phase 2: Vision & Computer Vision Core**

**Task 2.1: Vision Request Pipeline**

Implement VisionEngine as an ObservableObject. Subscribe to the CameraManager buffer stream. Inside the handler, create a VNImageRequestHandler and perform a VNDetectHumanHandPoseRequest. Configure maximumHandCount \= 2\. Extract .thumbTip, .indexFingerTip, and .wrist points for both hands. Publish these to a @Published variable structured as a custom HandLandmarks struct.

**Task 2.2: Coordinate Normalization & Overlay**

Create a SwiftUI OverlayView using the Canvas API. Accept normalized Vision points (0.0-1.0). Use GeometryReader to scale points to screen dimensions. Draw filled circles at thumb/index positions and a line connecting them. Draw a line connecting left wrist to right wrist. Ensure mirroring logic is applied so user movements feel natural (mirror image).

### **Phase 3: Signal Processing & Math**

**Task 3.1: Kalman Filter Implementation**

Implement KalmanScalar class to smooth noisy 60fps data. Maintain state x and covariance p. Define update(measurement) \-\> Double applying standard Kalman prediction/update with process noise q (\~0.005) and measurement noise r (\~0.05). Instantiate separate filters for X and Y coordinates of every tracked landmark.

**Task 3.2: Gesture State Machine**

Develop logic to translate coordinates to control values. Calculate Euclidean distance between Thumb/Index. Implement "Relative Clutch": when pinch distance \< 20pt, capture current audio parameter as "anchor". As user expands pinch, calculate ratio and apply to anchor. This prevents values jumping on initial pinch.

**Task 3.3: No-Hands Auto Pause**

Implement debounce timer for "No Hands". If Vision returns 0 results, start 1.0s background timer. If timer completes, signal Audio Engine PAUSE. If hands detected before completion, invalidate timer. If hands return after pause, signal PLAY.

### **Phase 4: Audio Engine Architecture**

**Task 4.1: Local Audio Engine (DSP)**

Implement LocalAudioStrategy using AVAudioEngine. Construct node graph: AVAudioPlayerNode \-\> AVAudioUnitTimePitch \-\> AVAudioMixerNode \-\> mainMixerNode. Expose methods to set pitch (cents, \-2400 to \+2400) and rate (0.1 to 2.0). Handle AVAudioSession interruptions.

**Task 4.2: Streaming Services Wrapper**

Implement MPMediaStrategy (Apple Music) and SpotifyStrategy (SPTAppRemote). These must conform to AudioStrategy protocol. For these strategies, setPitch and setSpeed must be no-ops or trigger UI toast "DRM Locked".

### **Phase 5: Data & Integration**

**Task 5.1: Video-to-Audio Importer**

Build MediaImporter service using PHPickerViewController (Video filter). Load AVAsset, init AVAssetExportSession with AVAssetExportPresetAppleM4A. Export asynchronously to app's Document directory. Register new file in local playlist.

**Task 5.2: Document Picker**

Implement UIDocumentPickerViewController for public.audio. Delegate must call startAccessingSecurityScopedResource(), FileManager.copyItem to local sandbox, then stopAccessingSecurityScopedResource(). Engine must play local copy only

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAsAAAAYCAYAAAAs7gcTAAAA5klEQVR4XmNgGAV0BwoKCgZycnLOKioq7CA+kBYFipmjKDI2NmYFCq4C4oXy8vKTgPgyUFMdkJ4NxOuBuA+uGKioE4gjQGwtLS02oOR/IP+QtLS0MJD9G4j3wRUDTelHYmuDFANxMpDLCKSLFBUV1eGKkQFQMguqWBFdDgMAFa0F4ofo4jDAArS6DaggCMhmBtLvgHgJTBLIDobKgT1nD7U2C6jJF8QGeRgkp6SkxA/krwcZCFasrKwsBpTcBMQTgBKTgTgQiB8ANc4A4g2ysrI6MFvgQB7JQ0CNHDIyMtLI8qMAHQAAx/8yMwx1QJkAAAAASUVORK5CYII=>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAsAAAAXCAYAAADduLXGAAABGUlEQVR4XmNgGNSACV0AF2BRUFBYKS8vPw3IZkSXhANjY2NWoKL1QNwHxLPk5OTmM+CyBWhiPFBRNowPZFcBcRCyGvKAtLS0DNBqXxkZGSEQX0VFhR1om4OWlhYbikKgYCUQ7wLRQKtfAOlCIN4I1NwO5J+FKwRyPIGCM5D4R4H4jaysrBRQwykg+xuQ5oBJVgOtFEVS/AqIF4PYQEXhQINcYHIoACihBVT4H6goEV0OAwAV54IUA2kldDkwAIUvULIOyt4EVPwEJqeoqCgP8iSYAwoWoOQPoKJVysrKYkD2d6DkSahaJqD4QiUlJTmYZpDVM4CKZgHxEqCkPZC+A+VvAeJguEIYACqSAEYGJ5TLBFSkiKJgJAAAzrs7sWJUcOQAAAAASUVORK5CYII=>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAYCAYAAAAlBadpAAABEUlEQVR4XmNgGOFATk7OWl5e/jYQPwPiF1D6HhDfAeL7QHwYqCZWS0uLDV0vHAAVrAAq/A/EljAxBQUFDiA/Byreh6weBUBt+wBkMmORewjEf5SUlOTQ5RikpaVloKZvRpcDAiag+Bcg/gd0iQK6JMjkaKjmEixyjiA5oLcWoMuBAVByNlSBMbK4oqKiPNCyU0C5x0C2OLIcHMhDQvsfENcADSgH0tVAvBSIPwD584FYEF0PGCD59yzQFn8QBir2AdIOoNBGV48CgApjQJqBChvQ5QgCoMa5UM0O6HIEgTwkFX1XUVFhR5fDC4AhqA6yFej0g+hyOAFQgyXQmbeA9DuQrUD8DYgfA3EwutpRMGQBAAqzTELtGlDYAAAAAElFTkSuQmCC>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAZCAYAAADuWXTMAAABjUlEQVR4Xt2SO0sDQRSFJUREfFVhCSSbZInsD1htfTUWNv4BQcHWZ6M2aiWKoCKCvdha+CoE/4BiIQh2aqWxEGIjEjHqd8NknZkkNlZ64HBnzjl3ZnZ26ur+H7LZbEMmk+lKpVIDMG77VUGDn06nD1zXPaNuULdpzlFP8Bw7H4LwHMEn6oiuO47ThH4N72KxWLPulcDK65jvsNf2BCzYj/dJbsE2BsWgLhqGBjmyZOBFKHqe14ZwD/NyPC1fATJFyenCtFpxVctVQC5S5W5DkcmpEvu0bAW0TY5LQhAE9UwKsMh/bbXyBsqbcC9TJeFXzfKKED5gzsoa8H2/hcwbfEgkEo2hgXADXxlGvuMm1CuTXYcNA3FHDLlNFZwhtE+dkDnjSfGZLxmNAow4zMM9gj2ExkVnvCzPFL1QtbGMZDLZSegKPsNDmmbhOeNLvA4VixjfayHKDgEckucKV2jeKpvo87xGV2+oCcJjNL/ANXgEd+1MTbBzt1yU4iNHbrczPyFK0yjc5BSebf5RfAHzeXJkKRk9dwAAAABJRU5ErkJggg==>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAYCAYAAAAlBadpAAABPklEQVR4Xu2RPS8EURSGN+ZXMB93JlPQ0mxWJ5HQEI2K2ra7tU6j8BMWBfHRSERCouQHaBWCbCFUSyLZCBKeu3tmnHujUGl4kydz7/uec+bemUrlj8sYMw7XcA8PcCf7NlzCZpqmVb/PUZIk+xR+QE2sIMsytmYP3slnnAYtCm7giWWgfd46YofyPNd+qTAMIyk48jP8CTnRlZ/1RLAgzc1vsnWbcex5P+uJsCXTRwsvjuMh9jvwSOOSrndkjwRvcCJcwAvswqBfX6q4L9MPlR3gbUOHLz6sfFc0Ldpm/77sp60Py9p3RLghRWPap7kh/or2HRHemv7/HfD8AzlRQ/ul7H1k+rGfcZ0zaa7bPeutKIpCe6Sq6X/hDnThGdr4U0Uzv2oW75Uhp7DKeu1r9A+U53nMwDmaJ/3sX7+hT8PdXvxovNjGAAAAAElFTkSuQmCC>

[image6]: <data:image/png;base64,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>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACcAAAAXCAYAAACI2VaYAAACvElEQVR4Xu2VSWgUQRSGJ4m7qKcwMltnljg6IBobRDwIgigGTx7UgBLIQRAMESJ4cEEQjCEiHgKCXlRkPHgT1AQiitso4gIiRD158KAoigpiBOP3MlWx5s3CzCFkQH/46X7/+6vq9evq6kDgP6YRqVRqodbqAsFgcH4sFhvW+pSgJY9OrZcDhe3Cv0/JDehbYB+5jmQyGVV5QSO57bAf3wHP89q0YQIklmE6wfUJ/A2vaU85MPEQYxfbOBqNhhg/Ag/F4/F1XM/CH3h2WA/3c9BuwmPm4a7Kutwft55JMMlqkl0kfa4/qy0uEomE8V53NRY6jfaR6xqJM5nMLOJf8DP+ucZzlPgct012HPFzOA7brVaEWoqT1wF3uhpjB2QR6YjEpktj8HsoFJpnPNLZcbeb+I+Y4i5ZrQi1FIfvoXwQSm6kQ602wLPWLHrZ0bpgLpFILLEaxW0zvotWK0K1xeFpqzhRYOK1t+J5xsKP6FKLzrvwTMfhVp2bRA3FnWKvbtS6BQWdwfMSfqDI5TrvgnOyGd8X+MLuy5IwxRVs8hJowvNUrjqhQZEb8H6Dh3XOglwWjobD4YjOFcAUd0PrLshvhie1Xg54H3j5jyRTIncQPpbu6VwRqiwuyytdoXUBBfSQ3+tqbLcLprg+pXeij6TT6QUSyyvFs9v1FECKwzCkdQuZCE9O6wLZ9FKEUA5jqxPfEo30Hse7Ce0KHZvt+OTLHrRxAXzfn0lyjIF3CGfovMA87X6tC2Qhcm9h1mpy1BB/EsqhLRr3q+BXeM/L/yluw7vwHY3p/jtj3twO30jSDBK+p5DXnEWLXC+Dh92uaMjZxdhROAh7YQ6+Yq6V1kN83zMd1qx0AlSE+W9W3I8GDXJ8UFAHD5PQySmBdEL/ruoGshdL/K6mHxS2lK6d13pdgFe6nuJ8rf+z+APU98V86Cn3BAAAAABJRU5ErkJggg==>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAAXCAYAAADpwXTaAAABtElEQVR4Xu2TzytEURTH3ygMSlamxrx5b34QU0pNSoqQFTZ2JtkqpSxsx8KCKSyQIjspVv4DP0ohK8qPWJIsRAqlSHzOuHd6Ljsr5dS3+873+z3n3nvee5b1H78JXzgc7gIZ13VTsVjMNg0Stm03oY8KHMfpMHUxBBHWQToSiTSzLoJnCnq8PrgpsAx60aZZ36SOZ3/OpIRb1gbJE4lEAfkruA+FQkXK00J+GI/HSz11M3DvYEJzsuOkkFyxT5n85C/gKRgMFitPWnkWdJ26hTS70pxEHieo1AliozKtao5R1NNoH65bc8y1XG1wqbkvIU0xHEghJ3RN3Rv4OtWms6Zm0WAe4QTc0LTW1M3AtwMeQI2p5YKm7RgewYip6cDTrzxtpvYtMO2qeSR+0FrBtczR1GSXIcRBL8e4llSzjJeX68MfoVdrTuqzDzJkKRLIx6sN5FvCIQ9oTv4KuE3v35FMJvPlZWUTPsJCDBdgRRsCgUAJ+Z2Ak1QIR9My5/PlHIMN2Qxum/UUrOlaKxqNVkGcgTkwDPbAOeY67SEfc9QNTHCy8VwzFT6ZBw1SiFFT/I8/EB9uen7bSRs62AAAAABJRU5ErkJggg==>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABkAAAAXCAYAAAD+4+QTAAABkElEQVR4Xu2UP0sDQRDFg6iFiNgc6JE/FzgLo1iYxoiYRksrQQW/gJ1YGG0sRPIFbDRYKSIIVqK9lXZWgkWKYGEhVgpWCvqbsBuG1T2xs8iDx17evJl3s5BLpdr4z+jIZrNzuVyuGkXRGuega/gN9JWFrt5EoVDoZugZvMzn89OEVXh+hCXX6wLvLINreBvwE667niYwrVB8CsOwx2qyEazz2Kms34BnnqAFzuXEEAq3BJ1rjcYZaeKc0roPsrU3hOH9UuQ81DrauGna0roPiSHpdHrIhNS0zgYjZpM9rfuQGGKL7jC0YRN+qnUfEkMYMmFC9rVuQ+CJ1n1QL1txa3JdsRl2oPVMJjNq9F2t+6BCNtxaKgiCXoof7rWgTXqbfkBiiIDiFbzRGqFL0sSfc8xqcRwHsrn2WdgQ+jbdWhMUFjG8cUWh1fh9JOHKJloDvuOPtC5AKksIrLq1FijuwHvWXeU8hte8eZ/jOYF3csVWY/g2Wh0+wxf4Ch/ghe5tgYYB84koFYvFLrfeRht/whfug3eTJ+VypwAAAABJRU5ErkJggg==>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABkAAAAXCAYAAAD+4+QTAAAB6UlEQVR4Xu2TPUhbURiGQwytisVSyGD+7iUE0wY6i4ODQ4duIgUNImKIgrR16GLrZEGQII6KQ4ObdHJqcZGaQR0UnII6CO5upTpobfX5zDnxy2nq5FCoL7zc+z3nPb/33EDgXv+skslkq+/7Y57nzSYSiXGebW7mb6LfY/oM8izQL5dKpR66GZmgncA2wbd4lGAZn8B63KyraDQaI7uH53An/Rd57sdisSc1QWCJAYdszUrCsAt8Ku8664pBP5P7ohn1JnxJsyDwHP+Ox+MRFfyGL3Feh7XMYs7wO82pp80Cb44NsIC/8hpymEySqwYdyXFKhuew5jKpcBbdpfkfIrSDL247Lo5kxEyS1Rz22vA+zWtE5xdmF5/cNi0G+VBvML9yS4WPaV5VOp1+ROAAr2QymQduuxaDvDeD9Tv8ehK5qZpbhWhcxUXeG9xGV+TyZscDDn9jeK/mtrHIKgq25q4/h3XrjBZtL81Oao4FNml4h+ayxY9sb0IzCcNe2VouAROnbB2JRJrJnJKZsUxkfsjjgD4N85f/wOte5f8o4S38XXZjc9RH+CcL8hWTq77La1Bq+Y7Uh0SmbEaOpMmr/N2XdfyLcKPNUi/jcjgcbrHMDLomNh98A8/b9jsVEzzFWSZ45rbd6z/VFfp3iurj0FgcAAAAAElFTkSuQmCC>

[image11]: <data:image/png;base64,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>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAVQAAAAYCAYAAAClfwUWAAAQo0lEQVR4Xu1cCbhVVRU+DJXNahHKsPdmKBTLRCqHLMExcc7KTA3JWfMzwykV5ylTFIecUMkcs1A/ZwlEVDAVzBwSQQFNnEhRVESQ1//ftfZ9+6537n0Xnrz3yPN/3/rOPWuvvc/e+6y99tpr73OzrECBAgUKFChQoECBAgWWGf379/90t27dvmr5BdoOPXr06G55BQpUQ4eePXv+wHu/fghhFTJw3w1K9FkrWGCFoxPew114DxvahAJtB7yPP4F+bvkFVlp0hH1bHdfONqFFwODdGzQedAHodtCrUJxdcZ3Rr1+/L1r5lQHOudVQ/3+DZrMdoJmgF8D/fiqHdl4K/hyVmQU6Jk1vC6CO53LwWr6iI9KGtaW3xD7U/ppLXdHrC9rH7MMHILMnvWybtx5wQgcN7dWrV1eb1pZAu9YEvYG2bWLTWgPsEzz7RdThee1/9vffjMyG4L3sRaf5Lp4Gbz3Qjqncigaeu5nWk+OP9ZiNOjwH2lrTaW9Yf7Yj0gW2nFpoSbvwrMmgj0ANcBy/Y9OXG3hBR6LQKajYqpGHwfp18JaCHktlV0agXYPYaaD5Wc5M1L17968gbQHoetDGNr21gfexvdZnTcPfF7ybQP9VJfhumt4WQJ1u0L7dKPLQ36vg/tfKH5nK1wuUux/zhxZ6gyhnC5RzteW3BCjzKJQ5a+DAgZ+yaa2BLl26fMGLIWrAhPNtm07QyCB9Dq67cYXpZcJ71sq1BlCHW1lXvgubBt7PNO2q5enPlrYLea8DLchy7IIF2nEYZI+w/AqgIetA6CN0+rdsGvgPgs62/JURUQFpXHPSrgXtY/ltBbyT+1HP3+XwD0E9twWdw7a0B4PqxSvlRNUpJ40e0pLevXs7m9YcGGriYMtyyl0W4PkPgaZYfktArxtlzsA7OsCmtRbw/LuoAzCo37NpBPrullTXaWAxxvsmIq0GLyuYXKMF/ki2A7SLTasHLW0XnjsdfXW35Vt07dr185BdBNkzbFoFnHinDZz1bJqX5f+2lr8yAu04me1Eey9J+bg/AS/lzJTXlqDHwXrW2oyisaVMWxtUePY9dDDcZtOAjuC/C1qK+gab2BpQT27xini/0JvjUfYTlp8HyPWyvBQMqWkcr24ECVOx75sYIujFDqF6uKhVgcn0G1rPu2waAf5U6ghXiTZtRcNL+IZO1tE2zQIyW6vsj2xaBSB0kTb4FNx2NGnlzSkLDPx+fJl4ed9M2J3B2wzKthpvkHdV3G9L657IRHSiQYDsdlHegvmQtgXKGdS3b9/PJEmdmI8DOt6zrqDB1ZYNKGMtbee8KIPfvwDdhJ8djHibAfU51ovHVxWhnRhU1GF37dPDc9IGMw3vaYxNI8DvjfRdOOBsGldLRq9K0Hc4OFOvFTrRBffb9OnTp2cqB/6X6LXgGXuwDsi3P0NY1XQjgnnyVmqqvxU6orqzlHVI+XlwsrI4P8vRM06cSJsImXVsWi0gzzHatsNSvnpS02K9dAxtXmUMllBjnLHuA/PqljpgyBfyZAgnYSrqwZE2Te0DY5hVJyYNPe4Me+NTfj3t4koC+X6I/OvbNALP3037cAN9zhDWKZVhDF/T6FwyBLo+dTeVqQBnMxaq9AYKvBE0zHZsBArrD7mHnMTODgI9GHR56iUGeSXoHdARKnMaaHqWKJN2MpfgI1XZnmKlY7oqxdmgp0EjvBiZR4Mad/wei99/wXU+8m8JugW/j8H1ElznuSoG2stsyJdLI74JypjE+JKVa0ugfqN9M3Fr9jfb0Q4M6uXanwNTPpUfdXwEaS/ZTSUaLS+bAYxdMc46AXRB1DeUdQbvQXPxe7+Yz8sGx82gV0AXIe1Q6qoXHZyF++MT2YNwfw/LAC3mb1KPGpt4kDvcy/KzYilPY+1lE2r7VJ5LbS9jZueUXw2QO5b6mSXjgMaUOlht2V4LKGtPPh/Xc1M+eGeBt6/KcNKagOsY0IuZWXLXMc5Owe/z2Cegg2I+tRmLMBl+WeW4AfZGTE/hJZzWANqdkyfHuU5c1ANuhNOgjbL5aAjB/xfS/8xns5+CxtObaxfhZcJ7RcfKNWovZqSTKt8HeEu82KwLvegAbdc2UQb5LgXdC95C0GvUI1yvjel56BAk2MoMDQmNy0xFdTZ9GYUexXsqKO4Xge7UmeBkJzFZ5p/AF4Pro6D3o+HyYmA5Kw2J5SLP6bg/mL81PsVB9nrqeeB+spa9Ma7HJ0uJWXF5rEs8vqADY74USBuu6ZNwnWoHe71A3stQh/vzCGkTQfcpsR3j8by9bBnVwDwo5wbLT6FK0h4MKgcaZ+3jqBNeBiQHECe6q5yZ2PT9UWHLpyhi2MDJRtwAXG8hP8hu8I1RDmljqUNeDHGDT7xiL0bhtXif8Bk/nWz5FtSz+Cwvg7D8XKebY+jrPo05Srq/utajpLf1ALIjOEDxs4OOpQdwv4GVqwfIt6k+v7zDT++aOpip0fYyAQ3wYlwou3aUbW6ccdcbz7hVeZzEyht7Xhynl+M9+wv372U5Hjj4/wG973RSI0H+XpKX2CrrVTEp4X4bLxNhOV6JsbqVl9VkzXYRThy2Rclqo4OXWP/sVA73z4I+DEms2YuzWNLBCJ14PgT/9JRfE5ppCDKdi+sHrGiojBewUneCns40NKAKfqoTr3UfNgx59mLeOOviflekb8nfNABMA53De52h6XY/wWUaefh9BGU4wDQ/lxOMV5UUB9e91QUvLTepWOQTyi8t8SIvRRLzW5C3pGwP8HK8hOGXqghqUOv1bCC/Bjd56qGszk2gpC+novwdSXhP2+E6KOSEiegZeDnCxuN4FengzQeNBn9okGMw6+l7HMp0eq/4fZLK0ohPMPlpxF9JeckgqL2JkJW9PQ5QEtv0qySNq6y5qXwE+G8i/QTLrwXkGYE8V3lZ2S33GWPk78W6ooxHlMXxOTExIoxhl8YZDQR+v0AZTWt2nAUZxwOSd7FXkpcG9rp4j7QNcD813kfE8Qi6w6YRzONN/FRtClfKbFdH2IjP9ZSz8Y+rA1GzXerkLWAfRx4B3muga+I9yl9D63aakaPhHZvy1JizD0rHvaqiV/UjFwdqAWVPD/dDlHdiItoEXtznNzMTjyXQyIu1ETyjSEUdjeshaTzGy6CjQafx5kDh8u4nWdP4LpebjDWW+V6WfzQ0/RLRMqJXGxIPpL3Biwf3W8tPEdSgUpFtmoUqKPuRXkWzhDLXsmXkwTXGJ0+0aXnwqj/WAPlGw0DPrQQnk/q7dqNUB0sDaHjC5gCjp3N9wqt/ECSA7JlejHDZs/ayzMtdMXg5Y3mq5ddCkIE8h8Ygy/Ho6oVOUFzpvcp7J17ZWVZOPWF6YSemfF/nOLN9wrHFfnVJOAa8ddP3F0EZlW0SP2W4QOtfET8Ncva9AfQM6K/IO4Z1t3Hyau1KnrldwqPDV1Fn13hcq3wm3asugndI5KksV9CLrT5WAJ3QFULjLZ8AfyMtuBwbQ8VP0obWPKfpRclutnzCSfxhSa3NAaQvwrMmWb6FF0/ldsO7D/RkykvhNEAeqoQE6gX7xUnsti5ivMiWUQ1ejhpdaPkpwjIY1BUFPP8KrcMgm5YHJ0ayAbSZ4ccB8FPeq6F43eVsZnldlXA5Gnmhcelbsdvt6hkEBpB/FuXdG++dDsQq+sKNUBqaUryyHgQxpg/zvXmJ112etcCoeoldLuWxNFyn0ZuzMqjfoZRxZiPF1z/OaNgY/iuB7WWfpE6Lk5NC5RBehJdJOldPnYR4mFYRP4267Y2eWNRoF2OuDQzJJLyDyUs3QHH/R9B7JqbKsBU95rjZHWUngx5OeU3gxEI/n+Us8dhIpM3KKr0/Bq0bMFN8LREtQZeKZQ+CjbUyhBOvtEmsC+hEA88fXpaETTxI5F0t6FIxz1NRZeWMx/hc55BzbMQ3xt8qYi7LCpS9P8o4bhmopnKkgOxU18y5uKh0oQVLxpbCS2hiYbXNSwsvsXPWeQ3Dn8g2x93aIAfSG0CDOViCLvVVNq5KyjrrZWC8Q93wYnBLA9tLLPAfidyVme4JMH7ozEYa28HnOrO5pXVpoi+sm8pvYdPyoPpZMqaRh/vhQWOqiWjdQP4pWj+2teyRpUDa407iqqzDeXG/wdcxzjKZNJa6JHYYxDYszBrrzFDD3/P0gM/wVc6fusYJ9scpH+UfoPwmfR7tDFGjXdxcqrAxTkIDFWEb3D8VkslTeU+AHtDfPOu9ZgwdQfb35Ac5mcATG5XwoohUiF+mfCefFL7lzVEDegXgLQlJzBLohPszSbwJegyhWijBaxC5V3IEggYaz7wH5e+gMpd5MeZl8Nko+5GYLz4HNCCRKZ1W4EBB+lBvls0ahGccZV7Kb29A/a4BzbT8FGjjCdqPW9m01kCy7CspdD3wcuZvYTrwnXgZM+NkqnJxg6kD3uMoxuGStOlBN0oS3jTQbXy/QXaC4w41B/No/nbiBZc3sXA/Ruu/R+RlcuRvntdlczx+5E1sNoJ9r2VUeEh5oI5D9iGNAVYA/OEo4+JsOYyqa/xKrbRZY8HzrZp+ML1Yl5zB9nWMM5Ubz+fwt64eHgMt7ambdOxDn/NRjNd4NMe2TcskTMOTBQ322Bn7E/wPOIYjj8918il2yajValeQryJ59rh0/MnLSoCy5Z15/TKS56PLH8/QuycPNIIOW9SzoMcto64E+S+Hpo4MhKY5ObLEhj0O+oOXwfzPUOXwqhN3/3knR1tokKn8ZaOmfH4GVlU5vFj+OXjGKFbay+5t+ewfXfUgO4A8vjEKZd4Nujg96J73HHYgy6U8rtfGb8i52eVlYLwOet/LaQY+/zcxb3tCkM2AxVn+rM62zfSyifO2l89TZ7jEq1qRwLM2Qv2ew/VN7Uf250s+53B5HrRt/PqOujPOydc8IZXhM7wYtvNdEvPSWDBXILun8k6Wm9O9fDpdnuzx+2jw3gpyAN5uPPC4Fo90VWzqBZmoZzNPEN3kACtvvqTw4r2+neW8JwutS3mcWLAstxz/DRAkvjk/9dwskD7Wy4kb9kP5U+Z6xhkRxEDRPnB1Nw73w5ycZuEy+Grcn5dVjsNNvegonTLqB3WUYSx+IMT/oOBxurmaRh3iqYqK+GuQ90AZrkgY1+epgJ1SGV+lXZkYa9oy2rVxXmxUg0+MPuq/OZ+P979uko/P5ZFR9sn45Os+euC3BznCdV2o9il00KUHDQ930XA/zNe3NGWF185b+nPmyIvjWOgMs3beMiGCXovOgk02t2o8p+PyfObYnsDBgb75MI0T/r+B7zWe6sgD4555f8gTTLgggl5OXqy0Gj8PHAc02vjZmR4aiMcAORBzJwvwrwg55ydbEzAM/Z35o588ePOfEClqjbMU3BRKxxzHf+rJftzQFcda8axrHmq1K8Jr/DR61IpO1jOOYPw07w991K40CY8WWAng5MBxeSOgwAoHl/uzfPJ5pBdPekqWs9qiIfNysL3JV14F2g5evpYcmTpqXjaqH03lCnzCoGc8uVxdrr8lK7Bs0FXBR+jvrTW0wJDEk65KfFSXhRdZfoG2hZNTRO+qV8sNNW4Iv8SYqJUt8AmDl08tn6kVFinw8YHxWvT3HV7iZEdX+0YcaTuBJtU6+legbRDkf2D5WfqtoBvxTg+151cLfIIB5djFy5+BFGgnwCA93W7cFChQoECBAgUKFChQoED7wf8APwKj4iIumy0AAAAASUVORK5CYII=>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAUkAAAAYCAYAAAB3Lw9OAAAP1UlEQVR4Xu1cB5RWxRX+F0hCekxC0AXeHdg1WOKJhhQ1BUGNYol61CgaSxJjiUSi8YhoYtSjYldiiRJR7BELltgbsZdjiZooNlBjj2JBkaKb7/vvnX/nn33v/W/ZZQF93zn3/G/unT733Zm5M++vVEqUKFGiRIkSJUqUKFGiREG0trZ+KeaVKFFiMWGVVVb59MCBA1cTkY1BK3g+X0Tn3PJh3BJLHoMHD/5JkiRHxPwS3YehQ4d+sX///p+P+cs88IKvDXoG9DLoFdCLFn4O9DjoTLz0P4jTdReguJuijDVi/tKKlpaWb6C+J4HmoF/uw+8k/F4JmogXsT/C9+D3+3G6jyvQ7j3Q5lmmO6T/mv54HboHNIaTSpyWQPq+oJ3Yd7GsO4E6TEY5q8f8ZQGYjD+L+j9mfcs+5rvKPn8a9CzoUbxH4wYMGPC1OG1P9C/KPxo0D9QG2jeWxxg0aND3EO8pawfb8xJopqjOsF2PoT0T8uq8ROwGCv27NXItY/VGJRGUC0ELWam6BAXBlwPpJ4NGxLIhQ4Z8k2Ui79Ni2dII1HMs6vsO6Nzm5uavR7L9wH+XhGCfULasA21bD+06J+aHEFX2t/hSeh7GNwHveNAc0D8qKf2CvHelDiDdtrGsEZziingsYpiRuSvmF0Ge/nYnirQF8t2tr8YH7CYbnzdB9yPcK5B1qX87g6CcNWNZFrzNCdP069fvCwjvDf4LoGdg+AeGaYiu2I0ujafojPQWHnuHfFR4JWvIbSG/KNCQ9S39BrFs2LBhn4J8B8i+EsuWNqANY6wde8QyAvzlIf8I7bk+li3rQLvuBN0d8z3MGLJvrohlBGSHmvyXsQyrimb02c8rkd4VAfI8HLSg0RYP5Y4G7R/ziyBPf7sTRdoC+ZmsC+o0LJahfmdTBtou5HelfzsDlH+6dHKBIGpzZlciw26ykdbvZ8eyrtiNRR5PWmtLeGUsA3+Edf5TsawIUKkJSLuAM0QsW1ZAJUMbPgKdGctCQP7Qor6MSys4bhw/tOvIWOaB/vmF6c/esYzAi/ot06FbYllXgPzuBt0T82MgztU05DG/CHpKf4u0RXR73WEhY7Jr2Meo746xrCeAsmeg7OtifhYCm5M6sQK9IX8VNL/SCcPbCIs8nki0vVW4g5KDf4Z1/taxjD4QWma8BC2xDGkGY5uzIuT34vlRLpFdcKAB3gpI9+NKyizigbRDEG9Lpo1lPQXO7KjD6+wDtGdALA+B+l7vIv8t+4BGIuQRdHLjp8mHOSuijBGtra2fYRjpWsEbXgleCObNfrUglWgUVwpeHoLlQr4FXSYh3+nOgFuNar4orx/zaWlpGRTG4wEU6xAYwN2YJ2fxMB4B+d8sTqrPj20SnWRmhXwefKX1jQfy64vyf4g2/JT9Qx7Lt3qtivzmgyazXtCRL8fpCeoc4twU8z3SyiDYz3n66+EUG6b5AwmXM2adaQt1j30s6raog+noe6AZoe83q39dQR2IQR8h0m7O/qoEhgtpV2DdwB9nPvtRsd7FkHab8/tY5gH5XRbHBbxGdqMJ0VdHXTYN2yMFxzMTYkougSOUA4nw+aDZyHjXMD4B3u9EZ7Y/gqY5XW4/QBlfMBoMhG+3fB9nmJ1oael0vQo0HXRBfc5qIEQ76ALRbe4toJO8AelJoNx9rQ3VtuUB7RpSqTd8+4N3AtI+5YJtOgcPvPdBGzNMg4nna60//iW69TpZ1B88mXGQz37IYyLCH+L3EPxOs7q9FioRT3ERfAT8c0G/xfNtzvxRolsYpqPD/BTkORayixgPNBPhg3w+5NkY0qm+wMbv+rSJQtQJ/2YlQ3GDleQTnpfojM4DsJfS9Mt04EHQsajjePw+zNUg8COrFw8ymOddFh4V50E49W/9KuYTWWU00l+CBk50+8vdA8uYDvlZSeAnSxqMWWfaImZUQH8I+aY7XMjMRdp1PT+rf6UTOuAB3nKgKVa/sXxmPb2c+sW6WT4XOz3Mo204PMwnhDSYWAnI/2dxqsYsaWA3aB8Q5zrIzsfvXvi9m2mKjGdDiCr5AtElO4mK8wErIsH1Fg9UemfRl7w6Q9pK4V0Uem8Yj7MzK8Vfz7O4Dw9UZ/ok0KthmkRnVR6OHOB5fmnOBodxQ0C+FuT/zCLRjr1V1OCSri1idEW3QSz7z7EsD3zZ0E9T+SyqkLWDD1OiNu+URt4HiSrvnlbWEU5XlhyT6XatqLotEV3VvsiXDL/HMD4e1zHZKKZB+gm+LBuDi01+mfU7x7VNgpNIPB8r0VgYn/7IzEMPv8JBmZfHMg/Ubxsr7xqG8buGjw/Zk6CL6lNU40zy7bBJ5T2EtwrkDX14BOuedT+yURlp+uuBeGdB9ljFVlSit0Q4FkcxXHTMTN6wLdK+kDkDZY9D+vFODTANyc3grRrEzexf6bwO8GCIhocr2OrKE8//Br3jw5CfZnkd6BOJtilz4pQGEytXrZbnewg2NbIbBHjbSbvvnCtKLhZO9vK88cxFYIBCJee2gCuRN5Hh0IBfXS2Jbg2O8zyrOHnHRHGPkGjwkd+3UfmdbSZ+jcrmZcbjtaNXXHBKSoD3FuiMkNcTQJmz2T+g78SyPKBdOyLNGkZ8KXb2MjxPBW+mD+P5aPz0TnS2nm1bpiY878P+55UJpNnWXjKO1X5MZ1cpdsFjLxuD1xHlPoabm5s/x20JeA8xHpUMskOsPCponX9QdNfwcsizbdx8b0jSkLRvx/O2TdUX0tnBDX53Aq1OMv5OKWnoj6KBHsmtLOOEk5roTiPzMIngCtalGGCPRmWk6a/xd2C9k2DSxvO65IntDoqMmU9bpC2iKzMuXLZAlpuxbPxukHYantW/i6IDKGcceAtDt06itzxqq13Rd/YOHzYeV9k0gh2QYXPqkLSfllcPbvLshgfHmvXH7zZcYVM3XbClzhrPhgiUvM4fifCG5EswOxAIH2ANrC3tEXcd420Sxc0cfKTZzMpdx/MQ3sjyqVu1gce7SIx7eshf3LABYR/MjWUxEOewwSl+GNT5SMjmoU3LeZ7oy9nhSg14zzZQHBpe9kOHLQoVw+r6H9AliDsFvINjP1Pg2wq3bb1Er/BcGPBqM6/LOQkU81mn1Ykw482rUW/QcIeyRF0Rc9Kc6GIrLqPXQCt7WRHjTaBOR8U6GSKvDJOn6i/yvQH8eWF72NfgfRj7E/PGjCjSFm9UQNNjWR6y+reoDrAtYruZIF4dghVfbCd4R/bSkOcR2Jy8ifUmi1N3pcil2A0P0Q87WBfSfMQZHclTx7MhRO8MMdO6lRIbYPxDQz7C90ukIDRqon6XmuPbD77LOBUV9YtwNVXz4dmgssyRQdTarJKkHB550AiB1u8E0ch3OCWMITrYbbGihcAs24I4d8Z8AvwnksB/g/DK1pbfhPFsu0f+2JAfQtQgvVFJ2aI49al16LsYYr4t1Pm7noe0wy3tlmHcxGbevLaLXgDO3DZJ+/WfzUJ+sCKYEvI9qF/sI1G/7Iegp70sMN4bhmki8KV/sJJzMppXRpb+muFYCLo95Iu6cjr4rSVnzIgibUls5Yo4B8eyLOT1rxTUAWm/2VJzfcVI9OYH46zteU4Pq8iru47kIWZzXMbEkei9Tx70HR/LJMVuhECem0N+CugN0Dy+m+RnjWchsEDRawV1gwjepdaQOmsv6turu6qQqM/vIZNzS8yL6NXBF1uWO11t/prPrXqaxgpz6d/L2ZJa1I/BMutOnazMB/KWyU5P7HiIVIgQf3wRn2SiDvA2sW1UClj/qYme+NXB/Cg0fDVnuGu/ELwSaDRk65MvprjcVrTnUA/RLdK0mE/4fCVaDRHhVknUt8Xxrk0QCJ8Kegd59LV6bGR8OuprfmbRK1A1o8OVM8t0Gdc4RH2kC13Ky+1sRQAagTKGONsGJuqTfsEFW3DRA4jw0IfGe6HdEGBePCCr+eQIyEeCPzHkeRQpI0t/rY/muuBls9UyD05OsOdTvUxyxowo0pZE/Z/sZ952KISs/iWkoA6Yu4b6y3uWdfA6JXrAOCe89cB+B28uJ1ek3RrhzdtTVtPMlIyJVXTXyC+LboxvUmTZDZsQuHirHnISeN6SdXdmS7LG08fPBP1dlvDqWJao4WMhuzGM53NsmX4g6Bkfz+khDvM4jxVydljh7KXlVsFO4G7xDnTkvQllVAYOgDNlFb1KQGWrbZES9X88zWW95/Uk6KsSPZ1+UqJVGtsL3rXsg5AfoI+oY50+R38SyUMxbt/p973MG36ntwMyVxxUSuuz1JUmXwTIP/B9Sdil2xOcHSYQiDPDRUbN6nQVfaFOT8Or/mDR7VfVD5zoar7ukzPE2411Au0T8TlhHQd622V86SHthwRNiDMRurUi+TbePOjwOxv6aq9DeE+fNtEvNaqrPvNVVXUuBOKcFa6UQhQpw+XoL55vlPYXkivW6iVv0C7IZyvQXhQ0GjOiQFuoQ/z6ZH6RSd1DMvrXZIV0gATeK0nk/gJ/G9ANeOyN30eSYKdEiH6KejMe6Ve/NTqTqNocF93JtqtDvMnCr7aorx12eUmG3WC/iX4WSV9vFaKLoYt9OG88U+F0OcwZjp8y8ZSaPqPnXOB7wgD/TNRXwqNyrqaqhzJsTKJ3jS5z6igd4/R6Az89m4bBWI3xzOrPEj0tn0Ynus+bnYY8nnf6lQAPgGqGwanRvUN0ZrsR8S4Hz3n5kgDqMZj9IPoiUJn+BDpH9NqO/4wzFaKz8qxED2Xut/a9LXadIojHU/RJYdoQHBvI54TKHgNxRote2eFK4UKEb3DBLG6rHG4rtw/TJfpJ5QzWwQWrFTzvD95spwa8dp0j0etfdEPQX9XGOBbmeL8oeo3pgLwL3JCvJTqB/CUJrqigjl8VnXimgk4EXeHqP8NjvYYjzvuJrrDOi5Wd7aSOhrwQRcrI01+n789M0W3jJaK+dBpOHmBM864oV2zMhktKW2ysHhWdqPiOfiB6S6LucDQLkt2/ndIB8IeJ+spPw+9x+P1rogdWTfaJH29T1LmOTD+oAzx1r55dIM81RQ+feJ+zTbTNz4v2MXWH9ufErImNyLEbnKhoL65O1GV3Aej8cFLJG88ugX4yp5dH14tl3Gq5wAfJlV7KTNeL8SKeR28a3JjpQV9CrPxLGonOYFujk7fjcyzPQR97Uaqzo23Dq9enPGylnOpnMfRJO8mMYSuBleIDBA+XcYGWSpTme8zidweYr99mxkD/Lpf23a4HDVHW7sLpvb1MP5pHozIqDfSXq6JwS2iHZOEYFhqzvLZ0BVn921kdIJDGJXoPOOan5sV2L6b3N9NuOP0wgHVM3Y1V8sezRIlPDvCyXJm3ii1RokSJTyzsU9mP3Z+MlChRokS3AKvI3V32QVqJEiVKfLJBI5nlVytRokSJEiVKlChRokSJxYv/A6wmHpyDYPWhAAAAAElFTkSuQmCC>

[image14]: <data:image/png;base64,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>

[image15]: <data:image/png;base64,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>
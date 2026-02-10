{
  "project_metadata": {
    "name": "GestureFlow_Music_Player",
    "version": "1.0.0",
    "description": "iOS App for real-time DSP audio control via Vision hand tracking.",
    "target_platform": "iOS 17.0+",
    "device_family": "iPhone, iPad",
    "language": "Swift 5.9"
  },
  "architecture_specs": {
    "pattern": "MVVM (Model-View-ViewModel)",
    "reactive_framework": "Combine",
    "ui_framework": "SwiftUI",
    "hardware_dependencies": ["Front Camera", "Audio Output"]
  },
  "modules": [
    {
      "name": "VisionManager",
      "responsibility": "Camera capture and VNDetectHumanHandPoseRequest processing.",
      "output": "PassthroughSubject<HandLandmarks, Never>"
    },
    {
      "name": "SignalProcessor",
      "responsibility": "Kalman filtering and Gesture State Machine (Pinch/Drag logic).",
      "input": "HandLandmarks",
      "output": "ControlSignals (Speed, Pitch, Volume)"
    },
    {
      "name": "AudioConductor",
      "responsibility": "Hybrid Audio Engine managing AVAudioEngine (Local) and External Players (Streaming).",
      "input": "ControlSignals"
    },
    {
      "name": "LibraryManager",
      "responsibility": "Unified data source for Local Files, Apple Music, and Spotify.",
      "strategies": ["LocalFileStrategy", "MPMediaStrategy", "SpotifyRemoteStrategy"]
    }
  ],
  "task_system": {
    "phase_1_foundation": [
      {
        "id": "TASK-1.1",
        "title": "Project Scaffold & Permissions",
        "description": "Initialize the Xcode project using the SwiftUI App lifecycle. Immediately configure 'Info.plist' to include 'NSCameraUsageDescription' (for tracking), 'NSAppleMusicUsageDescription' (for library access), and 'NSPhotoLibraryUsageDescription' (for video-to-audio import). Create the root 'ContentView' containing a 'TabView' with a 'PageTabViewStyle'. Create three placeholder views: 'SettingsView', 'ActiveSessionView', and 'LibraryView'. Ensure the app compiles and requests camera permissions upon the first launch of the ActiveSessionView."
      },
      {
        "id": "TASK-1.2",
        "title": "Camera Capture Service",
        "description": "Create a 'CameraManager' class that inherits from 'NSObject' and 'ObservableObject'. Inside, configure an 'AVCaptureSession' with the '.high' preset to balance performance and quality. Attach an 'AVCaptureDeviceInput' for the front-facing wide-angle camera. Attach an 'AVCaptureVideoDataOutput', setting its pixel format to 'kCVPixelFormatType_32BGRA' and its delegate to 'self' on a dedicated background dispatch queue. Implement the 'captureOutput' delegate method to extract 'CMSampleBuffer' and publish it via a Combine 'PassthroughSubject<CVPixelBuffer, Never>'."
      }
    ],
    "phase_2_vision_core": [
      {
        "id": "TASK-2.1",
        "title": "Vision Request Pipeline",
        "description": "Implement the 'VisionEngine' class as an ObservableObject. This class should subscribe to the 'CameraManager' pixel buffer stream. Within the subscription handler, create a 'VNImageRequestHandler' and perform a 'VNDetectHumanHandPoseRequest'. You must strictly configure 'maximumHandCount = 2' and 'chirality' to distinguish left vs. right hands. Extract the '.thumbTip', '.indexFingerTip', and '.wrist' points for both detected hands and publish them to a '@Published' variable structured as a custom 'HandLandmarks' struct."
      },
      {
        "id": "TASK-2.2",
        "title": "Coordinate Normalization & Overlay",
        "description": "Create a SwiftUI 'OverlayView' that utilizes the 'Canvas' API for high-performance rendering. The view must accept the normalized points (0.0 to 1.0) from the VisionEngine. Use 'GeometryReader' to scale these points to the screen dimensions. Draw visual indicators (filled circles) at the thumb and index finger positions, and draw a line connecting them. Draw a separate line connecting the left wrist to the right wrist. Ensure the overlay logic handles the camera mirroring correctly so the user's movements feel natural."
      }
    ],
    "phase_3_signal_processing": [
      {
        "id": "TASK-3.1",
        "title": "Kalman Filter Implementation",
        "description": "Implement a 'KalmanScalar' class to smooth the noisy 60fps coordinate data. The class must maintain a state estimate 'x' and a covariance 'p'. Define an 'update(measurement) -> Double' method that applies the standard Kalman prediction and update steps using a process noise 'q' (tune to ~0.005) and measurement noise 'r' (tune to ~0.05). Instantiate separate 'KalmanScalar' instances for the X and Y coordinates of every tracked landmark (LeftThumbX, LeftThumbY, etc.) to ensure independent smoothing."
      },
      {
        "id": "TASK-3.2",
        "title": "Gesture State Machine",
        "description": "Develop the logic to translate smoothed coordinates into audio control values. For Pitch and Speed, calculate the Euclidean distance between the Thumb and Index finger. Implement a 'Relative Clutch' system: when the pinch distance falls below a 'lock threshold' (e.g., 20pt), capture the current audio parameter value as the 'anchor'. As the user moves the pinch (expanding or contracting relative to the start), calculate a ratio and apply it to the anchor value to determine the new Pitch/Speed. This prevents the value from jumping when the user first pinches."
      },
      {
        "id": "TASK-3.3",
        "title": "No-Hands Auto Pause",
        "description": "Implement a robust debounce timer mechanism for the 'No Hands' state. In the Vision processing loop, if the request returns 0 results, start a 1.0-second background timer. If the timer completes without interruption, signal the Audio Engine to PAUSE. If hands are detected before the timer completes, invalidate the timer immediately. If hands return after a pause is triggered, signal the Audio Engine to PLAY. This logic prevents music from stuttering if the camera loses tracking for a split second."
      }
    ],
    "phase_4_audio_engine": [
      {
        "id": "TASK-4.1",
        "title": "Local Audio Engine (DSP)",
        "description": "Implement 'LocalAudioStrategy' using 'AVAudioEngine' for imported files. Construct a node graph in the following order: 'AVAudioPlayerNode' -> 'AVAudioUnitTimePitch' -> 'AVAudioMixerNode' -> 'mainMixerNode'. Expose public methods to set 'timePitchNode.pitch' (measured in cents, range -2400 to +2400) and 'timePitchNode.rate' (range 0.1 to 2.0). Ensure the engine handles 'AVAudioSession.interruptionNotification' to pause/resume correctly during phone calls or backgrounding."
      },
      {
        "id": "TASK-4.2",
        "title": "Apple Music & Spotify Wrappers",
        "description": "Implement 'MPMediaStrategy' using 'MPMusicPlayerController.applicationMusicPlayer' and 'SpotifyStrategy' using 'SPTAppRemote'. These classes must conform to a shared 'AudioStrategy' protocol. Crucially, for these two strategies, the 'setPitch' and 'setSpeed' methods must be implemented as no-ops (empty functions) or trigger a UI toast explaining that DRM content does not support DSP, as strictly required by iOS limitations."
      },
      {
        "id": "TASK-4.3",
        "title": "Strategy Pattern Switcher",
        "description": "Create an 'AudioManager' class that acts as the facade. It should hold a reference to the currently active 'AudioStrategy'. When the user selects a song from the LibraryView, the AudioManager should instantiate the correct strategy (Local vs. Streaming) and seamlessly switch context, ensuring the previous strategy is stopped and deallocated."
      }
    ],
    "phase_5_library_integration": [
      {
        "id": "TASK-5.1",
        "title": "Video-to-Audio Importer",
        "description": "Build a 'MediaImporter' service utilizing 'PHPickerViewController' with a filter for videos. Upon user selection, load the underlying 'AVAsset'. Initialize an 'AVAssetExportSession' with the 'AVAssetExportPresetAppleM4A' preset to extract the audio track. Execute the export asynchronously and save the resulting .m4a file to the app's 'FileManager.default.urls(for: .documentDirectory)' path. Register this new file in the app's local playlist."
      },
      {
        "id": "TASK-5.2",
        "title": "Document Picker Integration",
        "description": "Implement 'UIDocumentPickerViewController' configured for 'UTType.audio'. When the delegate receives a URL, strictly follow the security protocol: call 'startAccessingSecurityScopedResource()', then immediately 'FileManager.copyItem' the file to the local app sandbox, and finally call 'stopAccessingSecurityScopedResource()'. The audio engine must only attempt to play the local copy, not the external reference."
      }
    ]
  }
}
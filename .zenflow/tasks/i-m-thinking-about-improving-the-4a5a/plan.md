# Street Vision Annotation Feature — Implementation Plan

## Overview
Add an interactive photo annotation layer to the Street Vision (Visual Mode) chat. When the AI responds to a photo with Spanish object descriptions, a new button appears on the assistant message bubble (top-right overlay). Tapping it opens a fullscreen view of the photo with infographic-style annotations: colored labels connected to objects by leader lines. Tapping a label speaks that Spanish word aloud using on-device TTS.

## Architecture Decisions
- **Object coordinates**: Second API call to GPT-4.1 vision model (`/v1/annotate`) asking for normalized (x, y) centers for each identified object. Feasible, accurate, same model already used for Street Vision.
- **Storage**: New SwiftData model `StreetAnnotation` keyed on `assistantMessageId`. Annotations stored as a JSON string. Cached like Loros — never re-fetched if already stored.
- **Rendering**: SwiftUI `Canvas` for leader lines + positioned `Button` labels in a `ZStack`. Label positions pushed outward from image center using vector math. TTS via on-device `AVSpeechSynthesizer` (same as Parrot word tap).
- **Button placement**: Overlay on top-right corner of assistant message bubble (`.overlay(alignment: .topTrailing)`), offset slightly outside. Opposite corner from the speaker button at bottom-right.
- **Cost**: 6 treats per annotation (lighter than streetView at 9). Cached annotations cost 0.

## Steps

### [x] Step 1: Technical Spec
Write spec + plan (this file).

### [x] Step 2: Server — annotate endpoint
- Add `annotate: 6` to `actionCosts` in `config.js`
- Add `POST /v1/annotate` to `index.js`: receives `imageData[]` + `objectList` text, calls GPT-4.1 vision, returns `{ annotations: [{label, x, y}] }`

### [x] Step 3: iOS — StreetAnnotation model
- Create `Chat/Annotation/StreetAnnotation.swift`
- `@Model class StreetAnnotation` with `assistantMessageId`, `userMessageId`, `sessionId`, `annotationsJSON`, `createdAt`
- `struct AnnotationItem: Codable, Identifiable` with `label`, `x`, `y`

### [x] Step 4: iOS — ProxyClient extension
- Add `struct AnnotateResult` + `func annotate(imageData:objectList:)` to `ProxyClient.swift`

### [x] Step 5: iOS — AnnotationService
- Create `Chat/Annotation/AnnotationService.swift`
- `@Observable class` with states: `idle`, `loading`, `ready([AnnotationItem])`, `failed(String)`
- Checks SwiftData cache first; falls back to server call; saves result

### [x] Step 6: iOS — AnnotationCanvasView
- Create `Chat/Annotation/AnnotationCanvasView.swift`
- Fullscreen dark overlay with `.scaledToFit()` image
- `GeometryReader` to compute rendered image frame → map (x,y) to screen coordinates
- SwiftUI `Canvas` for leader lines + dot at object point
- Positioned `Button` labels (colored, bold, rounded rectangle background)
- Tapping label plays TTS via `AVSpeechSynthesizer` with `es-ES` voice
- Loading spinner while fetching; error retry button

### [x] Step 7: iOS — MessageBubbleView
- Add `onAnnotate: (() -> Void)?` parameter
- When non-nil (and message is assistant), add overlay button at `.topTrailing` of `bubbleContent`
- `eye.circle.fill` SF Symbol, yellow color, dark circular background, offset x:10 y:-10

### [x] Step 8: iOS — ChatView
- Add `struct AnnotationTarget: Identifiable` with `assistantMessage` + `userMessage`
- Add `@State private var annotationTarget: AnnotationTarget?`
- Private helper `userMessageWithImages(preceding:)` to find preceding user message with images
- Wire `onAnnotate` closure in `messageList` ForEach
- Add `.fullScreenCover(item: $annotationTarget)` presenting `AnnotationCanvasView`

### [x] Step 9: iOS — EMOMORENEISAApp
- Add `StreetAnnotation.self` to the SwiftData schema array

### [x] Step 10: HomeScreen & NewSessionView redesign
- ModeSelectorView: bigger dog (460pt), new card style matching NewSessionView, renamed cards: Explore / Memorise words / Verbs & times with subtitles and illustration images
- NewSessionView: matching dog size (460pt), card order Street view → Choose topic → Your chats, "Your chats" opens SessionListView
- Explore in ModeSelectorView now opens NewSessionView directly; session creation flows to ChatView

### [x] Step 11: Dog bubble voice narration + ChatView back button
- Generated 15 MP3 files via Google Cloud TTS (Achird/es-ES, 0.9× speed) for all dog bubble phrases on both home screens
- Saved as `dog_bubble_0.mp3`–`dog_bubble_9.mp3` and `explore_bubble_0.mp3`–`explore_bubble_4.mp3` in Resources/
- ModeSelectorView: plays corresponding MP3 when each typewriter phrase begins
- NewSessionView: same; plays `explore_bubble_N.mp3` per phrase
- ChatView: added Back button (chevron.left + "Back") in navigationBarLeading toolbar
- Build 22 uploaded to TestFlight

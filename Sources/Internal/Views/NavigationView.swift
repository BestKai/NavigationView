//
//  NavigationView.swift of NavigationView
//
//  Created by Tomasz Kurylik
//    - Twitter: https://twitter.com/tkurylik
//    - Mail: tomasz.kurylik@mijick.com
//
//  Copyright ©2023 Mijick. Licensed under MIT License.


import SwiftUI

struct NavigationView: View {
    let config: NavigationGlobalConfig
    @ObservedObject private var stack: NavigationManager = .shared
    @ObservedObject private var screenManager: ScreenManager = .shared
    @ObservedObject private var keyboardManager: KeyboardManager = .shared
    @GestureState private var isGestureActive: Bool = false
    @State private var temporaryViews: [AnyNavigatableView] = []
    @State private var animatableData: AnimatableData = .init()
    @State private var gestureData: GestureData = .init()


    var body: some View {
        ZStack { ForEach(temporaryViews, id: \.id, content: createItem) }
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(createDragGesture())
            .onChange(of: stack.views, perform: onViewsChanged)
            .onChange(of: isGestureActive, perform: onDragGestureEnded)
            .onAnimationCompleted(for: animatableData.opacity, perform: onAnimationCompleted)
            .animation(.keyboard(withDelay: isKeyboardVisible), value: isKeyboardVisible)
            .background(config.backgroundColour)
    }
}
private extension NavigationView {
    func createItem(_ item: AnyNavigatableView) -> some View {
        item.body
            .padding(.top, getPadding(.top, item))
            .padding(.bottom, getPadding(.bottom, item))
            .padding(.leading, getPadding(.leading, item))
            .padding(.trailing, getPadding(.trailing, item))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(getBackground(item).compositingGroup())
            .opacity(getOpacity(item))
            .scaleEffect(getScale(item))
            .offset(getOffset(item))
            .offset(x: getRotationTranslation(item))
            .rotation3DEffect(getRotationAngle(item), axis: getRotationAxis(), anchor: getRotationAnchor(item), perspective: getRotationPerspective())
            .compositingGroup()
            .disabled(gestureData.isActive)
    }
}

// MARK: - Handling Drag Gesture
private extension NavigationView {
    func createDragGesture() -> some Gesture { DragGesture()
        .updating($isGestureActive) { _, state, _ in state = true }
        .onChanged(onDragGestureChanged)
    }
}
private extension NavigationView {
    func onDragGestureChanged(_ value: DragGesture.Value) { guard canUseDragGesture(), canUseDragGesturePosition(value) else { return }
        updateAttributesOnDragGestureStarted()
        gestureData.translation = calculateNewDragGestureDataTranslation(value)
    }
    func onDragGestureEnded(_ value: Bool) { guard !value, canUseDragGesture() else { return }
        switch shouldDragGestureReturn() {
            case true: onDragGestureEndedWithReturn()
            case false: onDragGestureEndedWithoutReturn()
        }
    }
}
private extension NavigationView {
    func canUseDragGesture() -> Bool { 
        guard stack.views.count > 1 else { return false }
        guard !stack.transitionsBlocked else { return false }
        guard stack.navigationBackGesture == .drag else { return false }
        return true
    }
    func canUseDragGesturePosition(_ value: DragGesture.Value) -> Bool { if config.backGesturePosition == .anywhere { return true }
        let startPosition = stack.transitionAnimation == .verticalSlide ? value.startLocation.y : value.startLocation.x
        return startPosition < 50
    }
    func updateAttributesOnDragGestureStarted() { guard !gestureData.isActive else { return }
        stack.gestureStarted()
        gestureData.isActive = true
    }
    func calculateNewDragGestureDataTranslation(_ value: DragGesture.Value) -> CGFloat { switch stack.transitionAnimation {
        case .horizontalSlide, .cubeRotation, .scale: max(value.translation.width, 0)
        case .verticalSlide: max(value.translation.height, 0)
        default: 0
    }}
    func shouldDragGestureReturn() -> Bool { gestureData.translation > screenManager.size.width * config.backGestureThreshold }
    func onDragGestureEndedWithReturn() { NavigationManager.pop() }
    func onDragGestureEndedWithoutReturn() { withAnimation(getAnimation()) {
        NavigationManager.setTransitionType(.push)
        gestureData.isActive = false
        gestureData.translation = 0
    }}
}

// MARK: - Local Configurables
private extension NavigationView {
    func getPadding(_ edge: Edge.Set, _ item: AnyNavigatableView) -> CGFloat {
        guard let ignoredAreas = getConfig(item).ignoredSafeAreas,
              ignoredAreas.edges.isOne(of: .init(edge), .all)
        else { return screenManager.getSafeAreaValue(for: edge) }

        if ignoredAreas.regions.isOne(of: .keyboard, .all) && isKeyboardVisible { return 0 }
        if ignoredAreas.regions.isOne(of: .container, .all) && !isKeyboardVisible { return 0 }
        return screenManager.getSafeAreaValue(for: edge)
    }
    func getBackground(_ item: AnyNavigatableView) -> Color { getConfig(item).backgroundColour ?? config.backgroundColour }
    func getConfig(_ item: AnyNavigatableView) -> NavigationConfig { item.configure(view: .init()) }
}

// MARK: - Calculating Opacity
private extension NavigationView {
    func getOpacity(_ view: AnyNavigatableView) -> CGFloat { guard canCalculateOpacity(view) else { return 0 }
        let isLastView = isLastView(view)
        let opacity = calculateOpacityValue(isLastView)
        return opacity
    }
}
private extension NavigationView {
    func canCalculateOpacity(_ view: AnyNavigatableView) -> Bool {
        guard view.isOne(of: temporaryViews.last, temporaryViews.nextToLast) else { return false }
        return true
    }
    func isLastView(_ view: AnyNavigatableView) -> Bool {
        let lastView = stack.transitionType == .push ? temporaryViews.last : stack.views.last
        return view == lastView
    }
    func calculateOpacityValue(_ isLastView: Bool) -> CGFloat { switch stack.transitionAnimation {
        case .no, .horizontalSlide, .verticalSlide, .cubeRotation: 1
        case .dissolve: isLastView ? animatableData.opacity : 1 - animatableData.opacity
        case .scale: calculateOpacityValueForScaleTransition(isLastView)
    }}
}
private extension NavigationView {
    func calculateOpacityValueForScaleTransition(_ isLastView: Bool) -> CGFloat { switch isLastView {
        case true: gestureData.isActive ? 1 - gestureProgress * 1.5 : 1
        case false: gestureData.isActive ? 1 : 1 - animatableData.opacity * 1.5
    }}
}

// MARK: - Calculating Offset
private extension NavigationView {
    func getOffset(_ view: AnyNavigatableView) -> CGSize { guard canCalculateOffset(view) else { return .zero }
        let offsetSlideValue = calculateSlideOffsetValue(view)
        let offset = animatableData.offset + offsetSlideValue + gestureData.translation
        let offsetX = calculateXOffsetValue(offset), offsetY = calculateYOffsetValue(offset)
        let finalOffset = calculateFinalOffsetValue(view, offsetX, offsetY)
        return finalOffset
    }
}
private extension NavigationView {
    func canCalculateOffset(_ view: AnyNavigatableView) -> Bool {
        guard stack.transitionAnimation.isOne(of: .horizontalSlide, .verticalSlide) || stack.navigationBackGesture == .drag else { return false }
        guard view.isOne(of: temporaryViews.last, temporaryViews.nextToLast) else { return false }
        return true
    }
    func calculateSlideOffsetValue(_ view: AnyNavigatableView) -> CGFloat { switch view == temporaryViews.last {
        case true: stack.transitionType == .push || gestureData.isActive ? 0 : maxOffsetValue
        case false: stack.transitionType == .push || gestureData.isActive ? -maxOffsetValue : 0
    }}
    func calculateXOffsetValue(_ offset: CGFloat) -> CGFloat { stack.transitionAnimation == .horizontalSlide ? offset : 0 }
    func calculateYOffsetValue(_ offset: CGFloat) -> CGFloat { stack.transitionAnimation == .verticalSlide ? offset : 0 }
    func calculateFinalOffsetValue(_ view: AnyNavigatableView, _ offsetX: CGFloat, _ offsetY: CGFloat) -> CGSize { switch view == temporaryViews.last {
        case true: .init(width: offsetX, height: offsetY)
        case false: .init(width: offsetX * offsetXFactor, height: 0)
    }}
}

// MARK: - Calculating Scale
private extension NavigationView {
    func getScale(_ view: AnyNavigatableView) -> CGFloat { guard canCalculateScale(view) else { return 1 }
        let scaleValue = calculateScaleValue(view)
        let finalScale = calculateFinalScaleValue(scaleValue)
        return finalScale
    }
}
private extension NavigationView {
    func canCalculateScale(_ view: AnyNavigatableView) -> Bool {
        guard stack.transitionAnimation.isOne(of: .scale) else { return false }
        guard view.isOne(of: temporaryViews.last, temporaryViews.nextToLast) else { return false }
        return true
    }
    func calculateScaleValue(_ view: AnyNavigatableView) -> CGFloat { switch view == temporaryViews.last {
        case true: stack.transitionType == .push && !gestureData.isActive ? 1 - scaleFactor + animatableData.scale : 1 - animatableData.scale * (gestureProgress == 0 ? 1 : gestureProgress)
        case false: stack.transitionType == .push || gestureData.isActive ? 1 - animatableData.scale * (gestureProgress - 1) : 1 + scaleFactor - animatableData.scale
    }}
    func calculateFinalScaleValue(_ scaleValue: CGFloat) -> CGFloat { stack.transitionsBlocked || gestureData.translation > 0 ? scaleValue : 1 }
}

// MARK: - Calculating Rotation
private extension NavigationView {
    func getRotationAngle(_ view: AnyNavigatableView) -> Angle { guard canCalculateRotation(view) else { return .zero }
        let angle = calculateRotationAngleValue(view)
        return angle
    }
    func getRotationAnchor(_ view: AnyNavigatableView) -> UnitPoint { switch view == temporaryViews.last {
        case true: .trailing
        case false: .leading
    }}
    func getRotationTranslation(_ view: AnyNavigatableView) -> CGFloat { guard canCalculateRotation(view) else { return 0 }
        let rotationTranslation = calculateRotationTranslationValue(view)
        return rotationTranslation
    }
    func getRotationAxis() -> (x: CGFloat, y: CGFloat, z: CGFloat) { (x: 0.00000001, y: 1, z: 0.00000001) }
    func getRotationPerspective() -> CGFloat { switch screenManager.size.width > screenManager.size.height {
        case true: 0.52
        case false: 1
    }}
}
private extension NavigationView {
    func canCalculateRotation(_ view: AnyNavigatableView) -> Bool {
        guard stack.transitionAnimation.isOne(of: .cubeRotation) else { return false }
        guard view.isOne(of: temporaryViews.last, temporaryViews.nextToLast) else { return false }
        return true
    }
    func calculateRotationAngleValue(_ view: AnyNavigatableView) -> Angle { let rotationFactor = gestureData.isActive ? 1 - gestureProgress : animatableData.rotation
        switch view == temporaryViews.last {
            case true: return .degrees(90 - 90 * rotationFactor)
            case false: return .degrees(-90 * rotationFactor)
        }
    }
    func calculateRotationTranslationValue(_ view: AnyNavigatableView) -> CGFloat { let rotationFactor = gestureData.isActive ? 1 - gestureProgress : animatableData.rotation
        switch view == temporaryViews.last {
            case true: return screenManager.size.width - rotationFactor * screenManager.size.width
            case false: return -rotationFactor * screenManager.size.width
        }
    }
}

// MARK: - Animation
private extension NavigationView {
    func getAnimation() -> Animation { switch stack.transitionAnimation {
        case .no: .easeInOut(duration: 0)
        case .dissolve, .horizontalSlide, .verticalSlide, .scale: .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500, initialVelocity: 6.4)
        case .cubeRotation: .easeOut(duration: 0.52)
    }}
}

// MARK: - On Transition Begin
private extension NavigationView {
    func onViewsChanged(_ views: [AnyNavigatableView]) {
        blockTransitions()
        updateTemporaryViews(views)
        resetOffsetAndOpacity()
        animateOffsetAndOpacityChange()
    }
}
private extension NavigationView {
    func blockTransitions() {
        NavigationManager.blockTransitions(true)
    }
    func updateTemporaryViews(_ views: [AnyNavigatableView]) { switch stack.transitionType {
        case .push, .replaceRoot: temporaryViews = views
        case .pop: temporaryViews = views + [temporaryViews.last].compactMap { $0 }
    }}
    func resetOffsetAndOpacity() {
        let animatableOffsetFactor = stack.transitionType == .push ? 1.0 : -1.0

        animatableData.offset = maxOffsetValue * animatableOffsetFactor + gestureData.translation
        animatableData.opacity = gestureProgress
        animatableData.rotation = calculateNewRotationOnReset()
        animatableData.scale = scaleFactor * gestureProgress
        gestureData.isActive = false
        gestureData.translation = 0
    }
    func animateOffsetAndOpacityChange() { withAnimation(getAnimation()) {
        animatableData.offset = 0
        animatableData.opacity = 1
        animatableData.rotation = stack.transitionType == .push ? 1 : 0
        animatableData.scale = scaleFactor
    }}
}
private extension NavigationView {
    func calculateNewRotationOnReset() -> CGFloat { switch gestureData.isActive {
        case true: 1 - gestureProgress
        case false: stack.transitionType == .push ? 0 : 1
    }}
}

// MARK: - On Transition End
private extension NavigationView {
    func onAnimationCompleted() {
        resetViewOnAnimationCompleted()
        resetTransitionType()
        unblockTransitions()
    }
}
private extension NavigationView {
    func resetViewOnAnimationCompleted() { guard stack.transitionType == .pop else { return }
        temporaryViews = stack.views
        animatableData.offset = 0
        animatableData.rotation = 1
        gestureData.translation = 0
    }
    func resetTransitionType() {
        NavigationManager.setTransitionType(.push)
    }
    func unblockTransitions() {
        NavigationManager.blockTransitions(false)
    }
}

// MARK: - Helpers
private extension NavigationView {
    var gestureProgress: CGFloat { gestureData.translation / (stack.transitionAnimation == .verticalSlide ? screenManager.size.height : screenManager.size.width) }
    var isKeyboardVisible: Bool { keyboardManager.height > 0 }
}

// MARK: - Configurables
private extension NavigationView {
    var scaleFactor: CGFloat { 0.46 }
    var offsetXFactor: CGFloat { 1/3 }
    var maxOffsetValue: CGFloat { [.horizontalSlide: screenManager.size.width, .verticalSlide: screenManager.size.height][stack.transitionAnimation] ?? 0 }
}


// MARK: - Animatable Data
fileprivate struct AnimatableData {
    var opacity: CGFloat = 1
    var offset: CGFloat = 0
    var rotation: CGFloat = 0
    var scale: CGFloat = 0
}

// MARK: - Gesture Data
fileprivate struct GestureData {
    var translation: CGFloat = 0
    var isActive: Bool = false
}

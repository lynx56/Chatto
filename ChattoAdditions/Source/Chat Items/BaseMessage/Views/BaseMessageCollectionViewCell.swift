/*
 The MIT License (MIT)

 Copyright (c) 2015-present Badoo Trading Limited.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import UIKit
import Chatto

public protocol BaseMessageCollectionViewCellStyleProtocol {
    func avatarSize(viewModel: MessageViewModelProtocol) -> CGSize // .zero => no avatar
    func avatarVerticalAlignment(viewModel: MessageViewModelProtocol) -> VerticalAlignment
    var failedIcon: UIImage { get }
    var failedIconHighlighted: UIImage { get }
    var selectionIndicatorMargins: UIEdgeInsets { get }
    func selectionIndicatorIcon(for viewModel: MessageViewModelProtocol) -> UIImage
    func attributedStringForDate(_ date: String) -> NSAttributedString
    func layoutConstants(viewModel: MessageViewModelProtocol) -> BaseMessageCollectionViewCellLayoutConstants
    func senderIdView(viewModel: MessageViewModelProtocol) -> UIView
    func senderIdHeight(viewModel: MessageViewModelProtocol) -> CGFloat
    func senderIdHorizontalOffset(viewModel: MessageViewModelProtocol) -> CGFloat
}

public struct BaseMessageCollectionViewCellLayoutConstants {
    public let horizontalMargin: CGFloat
    public let horizontalInterspacing: CGFloat
    public let horizontalTimestampMargin: CGFloat
    public let maxContainerWidthPercentageForBubbleView: CGFloat

    public init(horizontalMargin: CGFloat,
                horizontalInterspacing: CGFloat,
                horizontalTimestampMargin: CGFloat,
                maxContainerWidthPercentageForBubbleView: CGFloat) {
        self.horizontalMargin = horizontalMargin
        self.horizontalInterspacing = horizontalInterspacing
        self.horizontalTimestampMargin = horizontalTimestampMargin
        self.maxContainerWidthPercentageForBubbleView = maxContainerWidthPercentageForBubbleView
    }
}

/**
    Base class for message cells

    Provides:

        - Reveleable timestamp
        - Failed icon
        - Incoming/outcoming styles
        - Selection support

    Subclasses responsability
        - Implement createBubbleView
        - Have a BubbleViewType that responds properly to sizeThatFits:
*/

open class BaseMessageCollectionViewCell<BubbleViewType>: UICollectionViewCell, BackgroundSizingQueryable, AccessoryViewRevealable, UIGestureRecognizerDelegate where
    BubbleViewType: UIView,
    BubbleViewType: MaximumLayoutWidthSpecificable,
    BubbleViewType: BackgroundSizingQueryable {

    public var animationDuration: CFTimeInterval = 0.33
    open var viewContext: ViewContext = .normal

    public private(set) var isUpdating: Bool = false
    open func performBatchUpdates(_ updateClosure: @escaping () -> Void, animated: Bool, completion: (() -> Void)?) {
        self.isUpdating = true
        let updateAndRefreshViews = {
            updateClosure()
            self.isUpdating = false
            self.updateViews()
            if animated {
                self.layoutIfNeeded()
            }
        }
        if animated {
            UIView.animate(withDuration: self.animationDuration, animations: updateAndRefreshViews, completion: { (_) -> Void in
                completion?()
            })
        } else {
            updateAndRefreshViews()
        }
    }

    open var messageViewModel: MessageViewModelProtocol! {
        didSet {
            oldValue?.avatarImage.removeObserver(self)
            self.updateViews()
            self.observeAvatar()
            self.addBubbleViewConstraintsIfNeeded()
        }
    }

    public var baseStyle: BaseMessageCollectionViewCellStyleProtocol! {
        didSet {
            self.updateViews()
            self.addBubbleViewConstraintsIfNeeded()
        }
    }

    private var shouldShowFailedIcon: Bool {
        return self.messageViewModel?.decorationAttributes.canShowFailedIcon == true && self.messageViewModel?.isShowingFailedIcon == true
    }

    override open var isSelected: Bool {
        didSet {
            if oldValue != self.isSelected {
                self.updateViews()
            }
        }
    }

    open var useAutolayoutForBubbleView: Bool { false }

    open var canCalculateSizeInBackground: Bool {
        return self.bubbleView.canCalculateSizeInBackground
    }

    public private(set) var bubbleView: BubbleViewType!
    open func createBubbleView() -> BubbleViewType! {
        assert(false, "Override in subclass")
        return nil
    }

    public private(set) var avatarView: UIImageView!
    open func createAvatarView() -> UIImageView! {
        let avatarImageView = UIImageView(frame: CGRect.zero)
        avatarImageView.isUserInteractionEnabled = true
        return avatarImageView
    }

    public private(set) var senderIdViewContainer = UIView()
    private var senderIdView: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.commonInit()
    }

    public private(set) lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(BaseMessageCollectionViewCell.bubbleTapped(_:)))
        tapGestureRecognizer.delegate = self
        return tapGestureRecognizer
    }()

    public private (set) lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
        let longpressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(BaseMessageCollectionViewCell.bubbleLongPressed(_:)))
        longpressGestureRecognizer.cancelsTouchesInView = true
        longpressGestureRecognizer.delegate = self
        return longpressGestureRecognizer
    }()

    public private(set) lazy var avatarTapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(BaseMessageCollectionViewCell.avatarTapped(_:)))
        return tapGestureRecognizer
    }()

    private func commonInit() {
        self.avatarView = self.createAvatarView()
        self.avatarView.addGestureRecognizer(self.avatarTapGestureRecognizer)
        self.bubbleView = self.createBubbleView()
        self.bubbleView.isExclusiveTouch = true
        self.bubbleView.addGestureRecognizer(self.tapGestureRecognizer)
        self.bubbleView.addGestureRecognizer(self.longPressGestureRecognizer)
        self.tapGestureRecognizer.require(toFail: self.longPressGestureRecognizer)
        self.contentView.addSubview(self.avatarView)
        self.contentView.addSubview(self.bubbleView)
        self.contentView.addSubview(self.failedButton)
        self.contentView.addSubview(self.selectionIndicator)
        self.contentView.addSubview(self.senderIdViewContainer)
        self.contentView.isExclusiveTouch = true
        self.isExclusiveTouch = true

        let selectionTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
        self.selectionTapGestureRecognizer = selectionTapGestureRecognizer
        self.addGestureRecognizer(selectionTapGestureRecognizer)
    }

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return self.bubbleView.bounds.contains(touch.location(in: self.bubbleView))
    }

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let allowLongPressGestureRecognizerToBeRecognizedWithAnyOtherGestureRecognizersExceptTapGestures = gestureRecognizer === self.longPressGestureRecognizer && !(otherGestureRecognizer is UITapGestureRecognizer)
        let allowTapGestureRecognizerToBeRecognizedWithOtherTapGestures = gestureRecognizer === self.tapGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer
        return allowLongPressGestureRecognizerToBeRecognizedWithAnyOtherGestureRecognizersExceptTapGestures
            || allowTapGestureRecognizerToBeRecognizedWithOtherTapGestures
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer {
            let allowTapGesturestToWaitUntilLongPressGesturesFail = otherGestureRecognizer == self.longPressGestureRecognizer
            return allowTapGesturestToWaitUntilLongPressGesturesFail
        }

        guard let otherLongPressGestureRecognizer = otherGestureRecognizer as? UILongPressGestureRecognizer else {
            return false
        }

        let allowLongPressGestureToWaitUntilOtherLongPressGesturesWithSingleTouchFail = gestureRecognizer == self.longPressGestureRecognizer && otherLongPressGestureRecognizer.numberOfTouchesRequired == 1
        return allowLongPressGestureToWaitUntilOtherLongPressGesturesWithSingleTouchFail
    }

    open override func prepareForReuse() {
        super.prepareForReuse()
        self.removeAccessoryView()
        self.senderIdView?.removeFromSuperview()
        self.senderIdView = nil
    }

    public private(set) lazy var failedButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(BaseMessageCollectionViewCell.failedButtonTapped), for: .touchUpInside)
        return button
    }()

    // MARK: View model binding

    final private func updateViews() {
        if self.viewContext == .sizing { return }
        if self.isUpdating { return }
        guard let viewModel = self.messageViewModel, let style = self.baseStyle else { return }
        self.bubbleView.isUserInteractionEnabled = viewModel.isUserInteractionEnabled
        if self.shouldShowFailedIcon {
            self.failedButton.setImage(self.baseStyle.failedIcon, for: .normal)
            self.failedButton.setImage(self.baseStyle.failedIconHighlighted, for: .highlighted)
            self.failedButton.alpha = 1
        } else {
            self.failedButton.alpha = 0
        }
        self.accessoryTimestampView.attributedText = style.attributedStringForDate(viewModel.date)
        self.updateSenderIdView(from: viewModel, with: style)
        self.updateSelectionIndicator(with: style)

        self.contentView.isUserInteractionEnabled = !viewModel.decorationAttributes.isShowingSelectionIndicator
        self.selectionTapGestureRecognizer?.isEnabled = viewModel.decorationAttributes.isShowingSelectionIndicator

        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    private func observeAvatar() {
        guard self.viewContext != .sizing else { return }
        guard let viewModel = self.messageViewModel else { return }
        self.avatarView.isHidden = !viewModel.decorationAttributes.isShowingAvatar
        self.avatarView.image = viewModel.avatarImage.value
        viewModel.avatarImage.observe(self) { [weak self] _, new in
            guard let self = self else { return }
            self.avatarView.image = new
        }
    }

    private func updateSenderIdView(from viewModel: MessageViewModelProtocol,
                                  with style: BaseMessageCollectionViewCellStyleProtocol) {
        self.senderIdViewContainer.isHidden = !viewModel.decorationAttributes.isShowingSenderId
        if self.senderIdView == nil {
            self.senderIdView = style.senderIdView(viewModel: viewModel)
            if let sView = self.senderIdView {
                // for sure it is not null
                senderIdViewContainer.addSubview(sView)
                if viewModel.isIncoming {
                    let constraint = NSLayoutConstraint(item: sView, attribute: .left, relatedBy: .equal, toItem: senderIdViewContainer, attribute: .left, multiplier: 1, constant: 0)
                    senderIdViewContainer.addConstraint(constraint)
                } else {
                    let constraint = NSLayoutConstraint(item: sView, attribute: .right, relatedBy: .equal, toItem: senderIdViewContainer, attribute: .right, multiplier: 1, constant: 0)
                    senderIdViewContainer.addConstraint(constraint)
                }
            }
        }
    }

    // MARK: layout

    private var didAddConstraintsForBubbleView = false
    private func addBubbleViewConstraintsIfNeeded() {
        guard !self.didAddConstraintsForBubbleView, let viewModel = self.messageViewModel, let style = self.baseStyle else { return }
        guard self.useAutolayoutForBubbleView else { return }
        self.didAddConstraintsForBubbleView = true
        let layoutConstants = style.layoutConstants(viewModel: viewModel)
        let percentage = layoutConstants.maxContainerWidthPercentageForBubbleView
        let offset = layoutConstants.horizontalMargin + layoutConstants.horizontalInterspacing
        let xConstraint: NSLayoutConstraint
        if viewModel.isIncoming {
            xConstraint = bubbleView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: offset)
        } else {
            xConstraint = bubbleView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -offset)
        }

        NSLayoutConstraint.activate([
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: percentage),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            xConstraint
        ])
    }

    open override func layoutSubviews() {
        super.layoutSubviews()

        let layout = self.calculateLayout(availableWidth: self.contentView.bounds.width)
        self.failedButton.bma_rect = layout.failedButtonFrame
        if !self.useAutolayoutForBubbleView {
            self.bubbleView.bma_rect = layout.bubbleViewFrame
            self.bubbleView.preferredMaxLayoutWidth = layout.preferredMaxWidthForBubble
            self.bubbleView.layoutIfNeeded()
        }

        self.avatarView.bma_rect = layout.avatarViewFrame
        self.selectionIndicator.bma_rect = layout.selectionIndicatorFrame

        self.senderIdViewContainer.frame = layout.senderIdViewFrame

        if self.accessoryTimestampView.superview != nil {
            let layoutConstants = baseStyle.layoutConstants(viewModel: messageViewModel)
            self.accessoryTimestampView.bounds = CGRect(origin: CGPoint.zero, size: self.accessoryTimestampView.intrinsicContentSize)
            let accessoryViewWidth = self.accessoryTimestampView.bounds.width
            let leftOffsetForContentView = max(0, offsetToRevealAccessoryView)
            let leftOffsetForAccessoryView = min(leftOffsetForContentView, accessoryViewWidth + layoutConstants.horizontalTimestampMargin)
            var contentViewframe = self.contentView.frame
            if self.messageViewModel.isIncoming {
                contentViewframe.origin = CGPoint.zero
            } else {
                contentViewframe.origin.x = -leftOffsetForContentView
            }
            self.contentView.frame = contentViewframe
            self.accessoryTimestampView.center = CGPoint(x: self.bounds.width - leftOffsetForAccessoryView + accessoryViewWidth / 2, y: self.contentView.center.y)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        if self.useAutolayoutForBubbleView {
            return contentView.systemLayoutSizeFitting(.init(width: size.width, height: 0),
                                                       withHorizontalFittingPriority: .required,
                                                       verticalFittingPriority: .defaultLow)
        } else {
            return self.calculateLayout(availableWidth: size.width).size
        }
    }

    private func calculateLayout(availableWidth: CGFloat) -> Layout {
        let layoutConstants = self.baseStyle.layoutConstants(viewModel: self.messageViewModel)
        let parameters = LayoutParameters(
            containerWidth: availableWidth,
            horizontalMargin: layoutConstants.horizontalMargin,
            horizontalInterspacing: layoutConstants.horizontalInterspacing,
            maxContainerWidthPercentageForBubbleView: layoutConstants.maxContainerWidthPercentageForBubbleView,
            bubbleView: self.bubbleView,
            isIncoming: self.messageViewModel.isIncoming,
            isShowingFailedButton: self.shouldShowFailedIcon,
            failedButtonSize: self.baseStyle.failedIcon.size,
            avatarSize: self.baseStyle.avatarSize(viewModel: self.messageViewModel),
            avatarVerticalAlignment: self.baseStyle.avatarVerticalAlignment(viewModel: self.messageViewModel),
            isShowingSelectionIndicator: self.messageViewModel.decorationAttributes.isShowingSelectionIndicator,
            selectionIndicatorSize: self.baseStyle.selectionIndicatorIcon(for: self.messageViewModel).size,
            selectionIndicatorMargins: self.baseStyle.selectionIndicatorMargins,
            showSenderId: self.messageViewModel.decorationAttributes.isShowingAvatar,
            senderIdViewHeight: self.baseStyle.senderIdHeight(viewModel: self.messageViewModel),
            senderIdHorizontalOffset: self.baseStyle.senderIdHorizontalOffset(viewModel: self.messageViewModel)
        )
        var layoutModel = Layout()
        layoutModel.calculateLayout(parameters: parameters)
        return layoutModel
    }

    // MARK: timestamp revealing

    private let accessoryTimestampView = UILabel()

    var offsetToRevealAccessoryView: CGFloat = 0 {
        didSet {
            self.setNeedsLayout()
        }
    }

    public var allowAccessoryViewRevealing: Bool = true

    open func preferredOffsetToRevealAccessoryView() -> CGFloat? {
        let layoutConstants = baseStyle.layoutConstants(viewModel: messageViewModel)
        return self.accessoryTimestampView.intrinsicContentSize.width + layoutConstants.horizontalTimestampMargin
    }

    open func revealAccessoryView(withOffset offset: CGFloat, animated: Bool) {
        self.offsetToRevealAccessoryView = offset
        if self.accessoryTimestampView.superview == nil {
            if offset > 0 {
                self.addSubview(self.accessoryTimestampView)
                self.layoutIfNeeded()
            }

            if animated {
                UIView.animate(withDuration: self.animationDuration, animations: { () -> Void in
                    self.layoutIfNeeded()
                })
            }
        } else {
            if animated {
                UIView.animate(withDuration: self.animationDuration, animations: { () -> Void in
                    self.layoutIfNeeded()
                    }, completion: { (_) -> Void in
                        if offset == 0 {
                            self.removeAccessoryView()
                        }
                })
            }
        }
    }

    func removeAccessoryView() {
        self.accessoryTimestampView.removeFromSuperview()
    }

    // MARK: Selection

    private let selectionIndicator = UIImageView(frame: .zero)

    private func updateSelectionIndicator(with style: BaseMessageCollectionViewCellStyleProtocol) {
        self.selectionIndicator.image = style.selectionIndicatorIcon(for: self.messageViewModel)
        self.updateSelectionIndicatorAccessibilityIdentifier()
    }

    private var selectionTapGestureRecognizer: UITapGestureRecognizer?
    public var onSelection: ((_ cell: BaseMessageCollectionViewCell) -> Void)?

    @objc
    private func handleSelectionTap(_ gestureRecognizer: UITapGestureRecognizer) {
        self.onSelection?(self)
    }

    private func updateSelectionIndicatorAccessibilityIdentifier() {
        let accessibilityIdentifier: String
        if self.messageViewModel.decorationAttributes.isShowingSelectionIndicator {
            if self.messageViewModel.decorationAttributes.isSelected {
                accessibilityIdentifier = "chat.message.selection_indicator.selected"
            } else {
                accessibilityIdentifier = "chat.message.selection_indicator.deselected"
            }
        } else {
            accessibilityIdentifier = "chat.message.selection_indicator.hidden"
        }
        self.selectionIndicator.accessibilityIdentifier = accessibilityIdentifier
    }

    // MARK: User interaction

    public var onFailedButtonTapped: ((_ cell: BaseMessageCollectionViewCell) -> Void)?
    @objc
    func failedButtonTapped() {
        self.onFailedButtonTapped?(self)
    }

    public var onAvatarTapped: ((_ cell: BaseMessageCollectionViewCell) -> Void)?
    @objc
    func avatarTapped(_ tapGestureRecognizer: UITapGestureRecognizer) {
        self.onAvatarTapped?(self)
    }

    public var onBubbleTapped: ((_ cell: BaseMessageCollectionViewCell) -> Void)?
    @objc
    func bubbleTapped(_ tapGestureRecognizer: UITapGestureRecognizer) {
        self.onBubbleTapped?(self)
    }

    public var onBubbleLongPressBegan: ((_ cell: BaseMessageCollectionViewCell) -> Void)?
    public var onBubbleLongPressEnded: ((_ cell: BaseMessageCollectionViewCell) -> Void)?
    @objc
    private func bubbleLongPressed(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        switch longPressGestureRecognizer.state {
        case .began:
            self.onBubbleLongPressBegan?(self)
        case .ended, .cancelled:
            self.onBubbleLongPressEnded?(self)
        default:
            break
        }
    }
}

private struct Layout {
    private (set) var size = CGSize.zero
    private (set) var failedButtonFrame = CGRect.zero
    private (set) var bubbleViewFrame = CGRect.zero
    private (set) var avatarViewFrame = CGRect.zero
    private (set) var senderIdViewFrame = CGRect.zero
    private (set) var selectionIndicatorFrame = CGRect.zero
    private (set) var preferredMaxWidthForBubble: CGFloat = 0

    mutating func calculateLayout(parameters: LayoutParameters) {
        let containerWidth = parameters.containerWidth
        let isIncoming = parameters.isIncoming
        let isShowingFailedButton = parameters.isShowingFailedButton
        let failedButtonSize = parameters.failedButtonSize
        let bubbleView = parameters.bubbleView
        let horizontalMargin = parameters.horizontalMargin
        let horizontalInterspacing = parameters.horizontalInterspacing
        let avatarSize = parameters.avatarSize
        let selectionIndicatorSize = parameters.selectionIndicatorSize
        let showSenderId = parameters.showSenderId
        let senderIdViewHeight = parameters.senderIdViewHeight

        let preferredWidthForBubble = (containerWidth * parameters.maxContainerWidthPercentageForBubbleView).bma_round()
        let bubbleSize = bubbleView.sizeThatFits(CGSize(width: preferredWidthForBubble, height: .greatestFiniteMagnitude))
        let extraHeight: CGFloat = showSenderId ? senderIdViewHeight + 2 : 0
        let containerRect = CGRect(origin: CGPoint.zero, size: CGSize(width: containerWidth, height: bubbleSize.height + extraHeight))

        self.bubbleViewFrame = bubbleSize.bma_rect(
            inContainer: containerRect,
            xAlignament: .center,
            yAlignment: .center
        )

        self.failedButtonFrame = failedButtonSize.bma_rect(
            inContainer: containerRect,
            xAlignament: .center,
            yAlignment: .center
        )

        self.avatarViewFrame = avatarSize.bma_rect(
            inContainer: containerRect,
            xAlignament: .center,
            yAlignment: parameters.avatarVerticalAlignment
        )

        self.selectionIndicatorFrame = selectionIndicatorSize.bma_rect(
            inContainer: containerRect,
            xAlignament: .left,
            yAlignment: .center
        )

        let senderIdViewSize = CGSize(width: containerRect.width - parameters.senderIdHorizontalOffset, height: senderIdViewHeight)
        let xAlignment = isIncoming ? HorizontalAlignment.left : HorizontalAlignment.right
        self.senderIdViewFrame = senderIdViewSize.bma_rect(
            inContainer: containerRect,
            xAlignament: xAlignment,
            yAlignment: .top
        )

        // Adjust horizontal positions

        var currentX: CGFloat = 0

        if parameters.isShowingSelectionIndicator {
            self.selectionIndicatorFrame.origin.x += parameters.selectionIndicatorMargins.left
        } else {
            self.selectionIndicatorFrame.origin.x -= selectionIndicatorSize.width
        }

        currentX += self.selectionIndicatorFrame.maxX

        if isIncoming {
            currentX += horizontalMargin
            self.avatarViewFrame.origin.x = currentX
            currentX += avatarSize.width
            if isShowingFailedButton {
                currentX += horizontalInterspacing
                self.failedButtonFrame.origin.x = currentX
                currentX += failedButtonSize.width
                currentX += horizontalInterspacing
            } else {
                self.failedButtonFrame.origin.x = currentX - failedButtonSize.width
                currentX += horizontalInterspacing
            }
            self.bubbleViewFrame.origin.x = currentX
            if showSenderId {
                self.senderIdViewFrame.origin.x = parameters.senderIdHorizontalOffset
            }
        } else {
            currentX = containerRect.maxX - horizontalMargin
            currentX -= avatarSize.width
            self.avatarViewFrame.origin.x = currentX
            if isShowingFailedButton {
                currentX -= horizontalInterspacing
                currentX -= failedButtonSize.width
                self.failedButtonFrame.origin.x = currentX
                currentX -= horizontalInterspacing
            } else {
                self.failedButtonFrame.origin.x = currentX
                currentX -= horizontalInterspacing
            }
            currentX -= bubbleSize.width
            self.bubbleViewFrame.origin.x = currentX
            if showSenderId {
                self.senderIdViewFrame.origin.x = 0
            }
        }

        if showSenderId {
            self.bubbleViewFrame.origin.y = extraHeight
            self.avatarViewFrame.origin.y = extraHeight
        }

        self.size = containerRect.size
        self.preferredMaxWidthForBubble = preferredWidthForBubble
    }
}

private struct LayoutParameters {
    let containerWidth: CGFloat
    let horizontalMargin: CGFloat
    let horizontalInterspacing: CGFloat
    let maxContainerWidthPercentageForBubbleView: CGFloat // in [0, 1]
    let bubbleView: UIView
    let isIncoming: Bool
    let isShowingFailedButton: Bool
    let failedButtonSize: CGSize
    let avatarSize: CGSize
    let avatarVerticalAlignment: VerticalAlignment
    let isShowingSelectionIndicator: Bool
    let selectionIndicatorSize: CGSize
    let selectionIndicatorMargins: UIEdgeInsets
    let showSenderId: Bool
    let senderIdViewHeight: CGFloat
    let senderIdHorizontalOffset: CGFloat
}

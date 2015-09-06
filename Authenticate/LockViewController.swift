//
//  ViewController.swift
//  Authenticate
//
//  Created by Benjamin Andris Suter-Dörig on 09/05/15.
//  Copyright (c) 2015 Benjamin Andris Suter-Dörig. All rights reserved.
//

import UIKit
import LocalAuthentication
import Dispatch
import CoreImage

@objc public protocol LockViewControllerDelegate {
	func lockViewControllerAuthentication(controller: LockViewController, didSucced success: Bool)
	func lockViewControllerDidSetup(controller: LockViewController, code: String)
}

private enum CodeValidationResult {
	case OK
	case TooShort
	case Wrong
}

@objc public enum LockScreenMode: Int {
	case Setup
	case Authenticate
}

private class Keypad: UIView {
	var enterPrompt = "Enter PIN" {
		didSet {
			updateTextField()
		}
	}

	var wrongCodeMessage = "Wrong PIN" {
		didSet {
			updateTextField()
		}
	}

	var callback: (String) -> (CodeValidationResult) = {code -> CodeValidationResult in return .Wrong}
	var timeUnits = ["Sec", "Min", "Hours", "Days", "Months", "Years"]
	var wait: UInt = 0 {
		didSet {
			if wait > 0 {
				for button in digitButtons {
					button.enabled = false
				}
				deleteButton.enabled = false
				if wait < 60 {
					textField.placeholder = "\(wait) \(timeUnits[0])"
				} else if wait < 60 * 60 {
					textField.placeholder = "\(wait / 60) \(timeUnits[1])"
				} else if wait < 60 * 60 * 24 {
					textField.placeholder = "\(wait / 60 / 60) \(timeUnits[2])"
				} else if wait < 60 * 60 * 24 * 30 {
					textField.placeholder = "\(wait / 60 / 60 / 24) \(timeUnits[3])"
				} else if wait < 60 * 60 * 24 * 365 {
					textField.placeholder = "\(wait / 60 / 60 / 24 / 30) \(timeUnits[4])"
				} else {
					textField.placeholder = "\(wait / 60 / 60 / 24 / 365) \(timeUnits[5])"
				}
				textField.text = ""
			} else {
				for button in digitButtons {
					button.enabled = true
				}
				deleteButton.enabled = true
				updateTextField()
			}
		}
	}

	private var digitButtons: [UIButton] = []
	private let deleteButton = UIButton(type: .System) as UIButton
	private var enteredCode = ""
	private let textField = UITextField()
	private var showWrongPINMessage = false

	init() {
		super.init(frame: CGRect.zero)
		let chars = ["⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⌫"]
		for (var i = 0; i <= 9; i++) {
			digitButtons.append(UIButton(type: .System) as UIButton)
			digitButtons[i].setTitle(chars[i], forState: .Normal)
			digitButtons[i].tag = i
			digitButtons[i].addTarget(self, action: "digitButtonPressed:", forControlEvents: .TouchUpInside)
			addSubview(digitButtons[i])
		}
		deleteButton.setTitle(chars[10], forState: .Normal)
		deleteButton.addTarget(self, action: "deleteButtonPressed:", forControlEvents: .TouchUpInside)
		addSubview(textField)
		textField.userInteractionEnabled = false
		textField.textAlignment = .Center
		updateTextField()
		addSubview(deleteButton)
		layout()
	}

	@IBAction func digitButtonPressed(button: UIButton) {
		enteredCode += "\(button.tag)"
		if callback(enteredCode) == .Wrong {
			enteredCode = ""
			showWrongPINMessage = true
		} else {
			showWrongPINMessage = false
		}
		updateTextField()
	}

	@IBAction func deleteButtonPressed(button: UIButton) {
		if enteredCode.characters.count > 0 {
			let index = enteredCode.endIndex.advancedBy(-1)
			enteredCode = enteredCode.substringToIndex(index)
			updateTextField()
		}
	}

	func reset() {
		enteredCode = ""
		showWrongPINMessage = false
		updateTextField()
	}

	private func updateTextField() {
		if wait > 0 {
			return
		}
		if showWrongPINMessage {
			textField.placeholder = wrongCodeMessage
		} else {
			textField.placeholder = enterPrompt
		}
		var code = ""
		for (var i = 0; i < enteredCode.characters.count; i++) {
			code += " ●"
		}
		textField.text = code
	}

	private func layout() {
		let elementWidth = bounds.width / 3
		let elementHeight = bounds.height / 5
		textField.frame = CGRect(x: 0, y: 0, width: bounds.width, height: elementHeight)
		textField.font = UIFont.systemFontOfSize(min(elementWidth, elementHeight) * 0.5)
		for (var i = 1; i <= 9; i++) {
			digitButtons[i].frame = CGRect(x: (CGFloat(i) + 2) % 3 * elementWidth, y: floor((CGFloat(i) + 2) / 3) * elementHeight, width: elementWidth, height: elementHeight)
			digitButtons[i].titleLabel?.font = UIFont.systemFontOfSize(min(elementWidth, elementHeight) * 0.9)
		}
		digitButtons[0].frame = CGRect(x: elementWidth, y: 4 * elementHeight, width: elementWidth, height: elementHeight)
		digitButtons[0].titleLabel?.font = UIFont.systemFontOfSize(min(elementWidth, elementHeight) * 0.9)
		deleteButton.frame = CGRect(x: 2 * elementWidth, y: 4 * elementHeight, width: elementWidth, height: elementHeight)
		deleteButton.titleLabel?.font = UIFont.systemFontOfSize(min(elementWidth, elementHeight) * 0.5)
	}

	override func layoutSubviews() {
		layout()
	}

	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)!
	}
}

public class LockViewController: UIViewController, UIViewControllerTransitioningDelegate {
	private var keypad: Keypad = Keypad()
	private var isVerifying = false
	private var isUpdatingWait = false
	private var waitTime = 0.16
	private var background = UIVisualEffectView(effect: UIBlurEffect(style: UIBlurEffectStyle.Light))
	private var upBackground = UIView()
	private var downBackground = UIView()
	private var rightBackground = UIView()
	private var leftBackground = UIView()

	private var wait: UInt {
		get {
			return keypad.wait
		}
		set(wait) {
			keypad.wait = wait
			if (!isUpdatingWait) {
				updateWait()
			}
		}
	}

	public var code: String = "0000"
	public var reason: String = "Unlock " + (NSBundle.mainBundle().infoDictionary!["CFBundleName"] as! String)
	public var allowsTouchID = true
	public var mode = LockScreenMode.Authenticate
	public var codeLength = 4
	public var remainingAttempts = -1
	public var maxWait: UInt = 30

	public var delegate: LockViewControllerDelegate?

	public var wrongCodeMessage: String {
		get {
			return keypad.wrongCodeMessage
		}
		set(wrongCodeMessage) {
			keypad.wrongCodeMessage = wrongCodeMessage
		}
	}

	public var enterPrompt = "Enter PIN" {
		didSet {
			if !isVerifying {
				keypad.enterPrompt = enterPrompt
			}
		}
	}

	public var verifyPrompt = "Verify" {
		didSet {
			if isVerifying {
				keypad.enterPrompt = verifyPrompt
			}
		}
	}

	public var timeUnits: [String] {
		get {
			return keypad.timeUnits
		}
		set(timeUnits) {
			keypad.timeUnits = timeUnits
		}
	}

	private func updateWait() {
		if wait > 0 {
			isUpdatingWait = true
			let time = dispatch_time(dispatch_time_t(DISPATCH_TIME_NOW), Int64(NSEC_PER_SEC))
			weak var weakSelf = self
			dispatch_after(time, dispatch_get_main_queue(), { () -> Void in
				if let strongSelf = weakSelf {
					strongSelf.wait--
					strongSelf.updateWait()
				}
			})
		} else {
			isUpdatingWait = false
		}
	}

	private func validateCode(code: String) -> CodeValidationResult {
		if mode == .Authenticate {
			if code.characters.count < self.code.characters.count {
				return .TooShort
			} else if code == self.code {
				if let del = delegate {
					del.lockViewControllerAuthentication(self, didSucced: true)
				} else {
					dismissViewControllerAnimated(true, completion: nil)
				}
				return .OK
			} else {
				if remainingAttempts > 0 {
					remainingAttempts--
				}
				if remainingAttempts == 0 {
					if let del = delegate {
						del.lockViewControllerAuthentication(self, didSucced: false)
					} else {
						dismissViewControllerAnimated(true, completion: nil)
					}
					return .Wrong
				}
				if maxWait > 0 {
					waitTime *= 2
					if UInt(waitTime) > maxWait {
						wait = maxWait
					} else {
						wait = UInt(waitTime)
					}
				}
				return .Wrong
			}
		} else {
			if code.characters.count < codeLength {
				return .TooShort
			} else if isVerifying && code == self.code {
				if let del = delegate {
					del.lockViewControllerDidSetup(self, code: code)
				} else {
					dismissViewControllerAnimated(true, completion: nil)
				}
				return .OK
			} else if isVerifying {
				isVerifying = false
				keypad.enterPrompt = enterPrompt
				return .Wrong
			} else {
				isVerifying = true
				self.code = code
				keypad.enterPrompt = verifyPrompt
				keypad.reset()
				return .OK
			}
		}
	}

	init() {
		super.init(nibName: nil, bundle: nil)
		transitioningDelegate = self
		modalPresentationStyle = .Custom
	}

	required public init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)!
		transitioningDelegate = self
	}

	override public func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		keypad.callback = validateCode
		let context = LAContext()
		if allowsTouchID && mode == .Authenticate {
			context.canEvaluatePolicy(LAPolicy.DeviceOwnerAuthenticationWithBiometrics, error:nil)
			weak var weakSelf = self
			context.evaluatePolicy(.DeviceOwnerAuthenticationWithBiometrics, localizedReason: reason, reply: { (success, error) ->Void in
				if success {
					if let strongSelf = weakSelf {
						if let del = strongSelf.delegate {
							del.lockViewControllerAuthentication(self, didSucced: true)
						} else {
							strongSelf.dismissViewControllerAnimated(true, completion: nil)
						}
					}
				}
			})
		}
		view.addSubview(background)
		view.addSubview(keypad)

		leftBackground.backgroundColor = UIColor.blackColor()
		rightBackground.backgroundColor = UIColor.blackColor()
		upBackground.backgroundColor = UIColor.blackColor()
		downBackground.backgroundColor = UIColor.blackColor()

		view.addSubview(leftBackground)
		view.addSubview(rightBackground)
		view.addSubview(upBackground)
		view.addSubview(downBackground)
		setupView(view.bounds.size)
	}

	override public func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
		setupView(size)
	}

	private func setupView(size: CGSize) {
		let elementSize = min(min(size.width / 3, size.height / 5), 100)
		keypad.frame = CGRect(x: 0, y: 0, width: 3 * elementSize, height: 5 * elementSize)
		keypad.center = CGPoint(x: size.width / 2, y: size.height / 2)
		background.frame.size = size

		let maxSize = max(size.width, size.height)
		leftBackground.frame = CGRect(x: -maxSize, y: -maxSize, width: maxSize, height: 3 * maxSize)
		rightBackground.frame = CGRect(x: size.width, y: -maxSize, width: maxSize, height: 3 * maxSize)
		upBackground.frame = CGRect(x: -maxSize, y: -maxSize, width: 3 * maxSize, height: maxSize)
		downBackground.frame = CGRect(x: -maxSize, y: size.height, width: 3 * maxSize, height: maxSize)
	}

	public func animationControllerForPresentedController(presented: UIViewController, presentingController presenting: UIViewController, sourceController source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		return PresentController()
	}

	public func animationControllerForDismissedController(dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		return DismissController()
	}
}

private class PresentController: NSObject, UIViewControllerAnimatedTransitioning {
	@objc func transitionDuration(transitionContext: UIViewControllerContextTransitioning?) -> NSTimeInterval {
		return 0.3
	}

	@objc func animateTransition(transitionContext: UIViewControllerContextTransitioning) {
		let vc = transitionContext.viewControllerForKey(UITransitionContextToViewControllerKey)!
		transitionContext.containerView()!.addSubview(vc.view)
		vc.view.alpha = 0
		UIView.animateWithDuration(transitionDuration(transitionContext), animations: { () -> Void in
			vc.view.alpha = 1
			}) { (finished) -> Void in transitionContext.completeTransition(finished)}
	}
}

private class DismissController: NSObject, UIViewControllerAnimatedTransitioning {
	@objc func transitionDuration(transitionContext: UIViewControllerContextTransitioning?) -> NSTimeInterval {
		return 0.3
	}

	@objc func animateTransition(transitionContext: UIViewControllerContextTransitioning) {
		let vc = transitionContext.viewControllerForKey(UITransitionContextFromViewControllerKey)!
		vc.view.alpha = 1
		UIView.animateWithDuration(transitionDuration(transitionContext), animations: { () -> Void in
			vc.view.alpha = 0
			}) { (finished) -> Void in
				vc.view.removeFromSuperview()
				transitionContext.completeTransition(finished)
		}
	}
}
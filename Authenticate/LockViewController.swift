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
	func lockViewControllerAuthentication(_ controller: LockViewController, didSucced success: Bool)
	func lockViewControllerDidSetup(_ controller: LockViewController, code: String)
}

private enum CodeValidationResult {
	case ok
	case tooShort
	case wrong
}

@objc public enum LockScreenMode: Int {
	case setup
	case authenticate
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

	var callback: (String) -> (CodeValidationResult) = {code -> CodeValidationResult in return .wrong}
	var timeUnits = ["Sec", "Min", "Hours", "Days", "Months", "Years"]
	var wait: UInt = 0 {
		didSet {
			if wait > 0 {
				for button in digitButtons {
					button.isEnabled = false
				}
				deleteButton.isEnabled = false
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
					button.isEnabled = true
				}
				deleteButton.isEnabled = true
				updateTextField()
			}
		}
	}

	private var digitButtons: [UIButton] = []
	private let deleteButton = UIButton(type: .system) as UIButton
	private var enteredCode = ""
	private let textField = UITextField()
	private var showWrongPINMessage = false

	init() {
		super.init(frame: CGRect.zero)
		let chars = ["⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⌫"]
		for i in 0 ... 9 {
			digitButtons.append(UIButton(type: .system) as UIButton)
			digitButtons[i].setTitle(chars[i], for: UIControlState())
			digitButtons[i].tag = i
			digitButtons[i].addTarget(self, action: #selector(Keypad.digitButtonPressed(_:)), for: .touchUpInside)
			addSubview(digitButtons[i])
		}
		deleteButton.setTitle(chars[10], for: UIControlState())
		deleteButton.addTarget(self, action: #selector(Keypad.deleteButtonPressed(_:)), for: .touchUpInside)
		addSubview(textField)
		textField.isUserInteractionEnabled = false
		textField.textAlignment = .center
		updateTextField()
		addSubview(deleteButton)
		layout()
	}

	@IBAction func digitButtonPressed(_ button: UIButton) {
		enteredCode += "\(button.tag)"
		if callback(enteredCode) == .wrong {
			enteredCode = ""
			showWrongPINMessage = true
		} else {
			showWrongPINMessage = false
		}
		updateTextField()
	}

	@IBAction func deleteButtonPressed(_ button: UIButton) {
		if enteredCode.count > 0 {
			let index = enteredCode.index(enteredCode.endIndex, offsetBy: -1)
			enteredCode = String(enteredCode[..<index])
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
		for _ in 0 ..< enteredCode.count {
			code += " ●"
		}
		textField.text = code
	}

	private func layout() {
		let elementWidth = bounds.width / 3
		let elementHeight = bounds.height / 5
		textField.frame = CGRect(x: 0, y: 0, width: bounds.width, height: elementHeight)
		textField.font = UIFont.systemFont(ofSize: min(elementWidth, elementHeight) * 0.5)
		for i in 1 ... 9 {
			digitButtons[i].frame = CGRect(x: (CGFloat(i) + 2).truncatingRemainder(dividingBy: 3) * elementWidth, y: floor((CGFloat(i) + 2) / 3) * elementHeight, width: elementWidth, height: elementHeight)
			digitButtons[i].titleLabel?.font = UIFont.systemFont(ofSize: min(elementWidth, elementHeight) * 0.9)
		}
		digitButtons[0].frame = CGRect(x: elementWidth, y: 4 * elementHeight, width: elementWidth, height: elementHeight)
		digitButtons[0].titleLabel?.font = UIFont.systemFont(ofSize: min(elementWidth, elementHeight) * 0.9)
		deleteButton.frame = CGRect(x: 2 * elementWidth, y: 4 * elementHeight, width: elementWidth, height: elementHeight)
		deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: min(elementWidth, elementHeight) * 0.5)
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
	private var background = UIVisualEffectView(effect: UIBlurEffect(style: UIBlurEffectStyle.light))
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

	@objc public var code: String = "0000"
	@objc public var reason: String = "Unlock " + (Bundle.main.infoDictionary!["CFBundleName"] as! String)
	@objc public var allowsTouchID = true
	@objc public var mode = LockScreenMode.authenticate
	@objc public var codeLength = 4
	@objc public var remainingAttempts = -1
	@objc public var maxWait: UInt = 30

	@objc public var delegate: LockViewControllerDelegate?

	@objc public var wrongCodeMessage: String {
		get {
			return keypad.wrongCodeMessage
		}
		set(wrongCodeMessage) {
			keypad.wrongCodeMessage = wrongCodeMessage
		}
	}

	@objc public var enterPrompt = "Enter PIN" {
		didSet {
			if !isVerifying {
				keypad.enterPrompt = enterPrompt
			}
		}
	}

	@objc public var verifyPrompt = "Verify" {
		didSet {
			if isVerifying {
				keypad.enterPrompt = verifyPrompt
			}
		}
	}

	@objc public var timeUnits: [String] {
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
			weak var weakSelf = self
			DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
				if let strongSelf = weakSelf {
					strongSelf.wait -= 1
					strongSelf.updateWait()
				}
			}
		} else {
			isUpdatingWait = false
		}
	}

	private func validate(code: String) -> CodeValidationResult {
		if mode == .authenticate {
			if code.count < self.code.count {
				return .tooShort
			} else if code == self.code {
				if let del = delegate {
					del.lockViewControllerAuthentication(self, didSucced: true)
				} else {
					dismiss(animated: true, completion: nil)
				}
				return .ok
			} else {
				if remainingAttempts > 0 {
					remainingAttempts -= 1
				}
				if remainingAttempts == 0 {
					if let del = delegate {
						del.lockViewControllerAuthentication(self, didSucced: false)
					} else {
						dismiss(animated: true, completion: nil)
					}
					return .wrong
				}
				if maxWait > 0 {
					waitTime *= 2
					if UInt(waitTime) > maxWait {
						wait = maxWait
					} else {
						wait = UInt(waitTime)
					}
				}
				return .wrong
			}
		} else {
			if code.count < codeLength {
				return .tooShort
			} else if isVerifying && code == self.code {
				if let del = delegate {
					del.lockViewControllerDidSetup(self, code: code)
				} else {
					dismiss(animated: true, completion: nil)
				}
				return .ok
			} else if isVerifying {
				isVerifying = false
				keypad.enterPrompt = enterPrompt
				return .wrong
			} else {
				isVerifying = true
				self.code = code
				keypad.enterPrompt = verifyPrompt
				keypad.reset()
				return .ok
			}
		}
	}

	init() {
		super.init(nibName: nil, bundle: nil)
		transitioningDelegate = self
		modalPresentationStyle = .custom
	}

	required public init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)!
		transitioningDelegate = self
	}

	override open func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		keypad.callback = validate(code:)
		let context = LAContext()
		if allowsTouchID && mode == .authenticate {
			context.canEvaluatePolicy(LAPolicy.deviceOwnerAuthenticationWithBiometrics, error:nil)
			weak var weakSelf = self
			context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason, reply: { (success, error) ->Void in
				if success {
					if let strongSelf = weakSelf {
						if let del = strongSelf.delegate {
							del.lockViewControllerAuthentication(self, didSucced: true)
						} else {
							strongSelf.dismiss(animated: true, completion: nil)
						}
					}
				}
			})
		}
		view.addSubview(background)
		view.addSubview(keypad)

		leftBackground.backgroundColor = UIColor.black
		rightBackground.backgroundColor = UIColor.black
		upBackground.backgroundColor = UIColor.black
		downBackground.backgroundColor = UIColor.black

		view.addSubview(leftBackground)
		view.addSubview(rightBackground)
		view.addSubview(upBackground)
		view.addSubview(downBackground)
		setupView(view.bounds.size)
	}

	override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		setupView(size)
	}

	private func setupView(_ size: CGSize) {
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

	open func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		return PresentController()
	}

	open func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		return DismissController()
	}
}

private class PresentController: NSObject, UIViewControllerAnimatedTransitioning {
	@objc func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
		return 0.3
	}

	@objc func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
		let vc = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to)!
		transitionContext.containerView.addSubview(vc.view)
		vc.view.alpha = 0
		UIView.animate(withDuration: transitionDuration(using: transitionContext), animations: { () -> Void in
			vc.view.alpha = 1
			}, completion: { (finished) -> Void in transitionContext.completeTransition(finished)}) 
	}
}

private class DismissController: NSObject, UIViewControllerAnimatedTransitioning {
	@objc func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
		return 0.3
	}

	@objc func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
		let vc = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from)!
		vc.view.alpha = 1
		UIView.animate(withDuration: transitionDuration(using: transitionContext), animations: { () -> Void in
			vc.view.alpha = 0
			}, completion: { (finished) -> Void in
				vc.view.removeFromSuperview()
				transitionContext.completeTransition(finished)
		}) 
	}
}

//
//  ViewController.swift
//  Authenticate
//
//  Created by Benjamin Andris Suter-Dörig on 11/05/15.
//  Copyright (c) 2015 Benjamin Andris Suter-Dörig. All rights reserved.
//

import UIKit

public class ViewController: UIViewController, LockViewControllerDelegate {
	var code = "0000"
	
	@IBAction func setup(sender: AnyObject) {
		let lockVC = LockViewController()
		lockVC.mode = .Setup
		lockVC.delegate = self
		presentViewController(lockVC, animated: true, completion: nil)
	}
	@IBAction func authenticate(sender: UIButton) {
		let lockVC = LockViewController()
		lockVC.code = code
		lockVC.remainingAttempts = -1
		lockVC.maxWait = 3
		lockVC.delegate = self
		presentViewController(lockVC, animated: true, completion: nil)
	}

	public func lockViewControllerDidSetup(controller: LockViewController, code: String) {
		self.code = code
		dismissViewControllerAnimated(true, completion: nil)
	}

	public func lockViewControllerAuthentication(controller: LockViewController, didSucced success: Bool) {
		dismissViewControllerAnimated(true, completion: nil)
		dispatch_async(dispatch_get_main_queue(), { () -> Void in
			self.view.backgroundColor = success ? UIColor.greenColor() : UIColor.redColor()
		})
	}
}
//
//  ViewController.swift
//  Authenticate
//
//  Created by Benjamin Andris Suter-Dörig on 11/05/15.
//  Copyright (c) 2015 Benjamin Andris Suter-Dörig. All rights reserved.
//

import UIKit

open class ViewController: UIViewController, LockViewControllerDelegate {
	var code = "0000"
	
	@IBAction func setup(_ sender: AnyObject) {
		let lockVC = LockViewController()
		lockVC.mode = .setup
		lockVC.delegate = self
		present(lockVC, animated: true, completion: nil)
	}
	@IBAction func authenticate(_ sender: UIButton) {
		let lockVC = LockViewController()
		lockVC.code = code
		lockVC.remainingAttempts = -1
		lockVC.maxWait = 3
		lockVC.delegate = self
		present(lockVC, animated: true, completion: nil)
	}

	open func lockViewControllerDidSetup(_ controller: LockViewController, code: String) {
		self.code = code
		dismiss(animated: true, completion: nil)
	}

	open func lockViewControllerAuthentication(_ controller: LockViewController, didSucced success: Bool) {
		dismiss(animated: true, completion: nil)
		DispatchQueue.main.async(execute: { () -> Void in
			self.view.backgroundColor = success ? UIColor.green : UIColor.red
		})
	}
}

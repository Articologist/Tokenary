// Copyright © 2021 Encrypted Ink. All rights reserved.

import Cocoa

class ImportViewController: NSViewController {
    
    private let walletsManager = WalletsManager.shared
    var onSelectedWallet: ((InkWallet) -> Void)?
    private var inputValidationResult = WalletsManager.InputValidationResult.invalid
    
    @IBOutlet weak var textField: NSTextField! {
        didSet {
            textField.delegate = self
            textField.placeholderString = "Options:\n\n• Ethereum Private Key\n• Secret Words\n• Keystore"
        }
    }
    @IBOutlet weak var okButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func actionButtonTapped(_ sender: Any) {
        if inputValidationResult == .requiresPassword {
            showPasswordAlert()
        } else {
            importWith(input: textField.stringValue, password: nil)
        }
    }
 
    private func showPasswordAlert() {
        let alert = Alert()
        alert.messageText = "Enter keystore password."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let passwordTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
        passwordTextField.bezelStyle = .roundedBezel
        alert.accessoryView = passwordTextField
        passwordTextField.isAutomaticTextCompletionEnabled = false
        passwordTextField.alignment = .center
        
        DispatchQueue.main.async {
            passwordTextField.becomeFirstResponder()
        }
        
        if alert.runModal() == .alertFirstButtonReturn {
            importWith(input: textField.stringValue, password: passwordTextField.stringValue)
        }
    }
    
    private func importWith(input: String, password: String?) {
        do {
            let wallet = try walletsManager.addWallet(input: input, inputPassword: password)
            showAccountsList(newWalletId: wallet.id)
        } catch {
            Alert.showWithMessage("Failed to import account", style: .critical)
        }
    }
    
    private func showAccountsList(newWalletId: String?) {
        let accountsListViewController = instantiate(AccountsListViewController.self)
        accountsListViewController.onSelectedWallet = onSelectedWallet
        accountsListViewController.newWalletId = newWalletId
        view.window?.contentViewController = accountsListViewController
    }
    
    @IBAction func cancelButtonTapped(_ sender: NSButton) {
        showAccountsList(newWalletId: nil)
    }
    
}

extension ImportViewController: NSTextFieldDelegate {
    
    func controlTextDidChange(_ obj: Notification) {
        inputValidationResult = walletsManager.validateWalletInput(textField.stringValue)
        okButton.isEnabled = inputValidationResult != .invalid
    }
    
}

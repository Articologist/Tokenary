// Copyright © 2021 Encrypted Ink. All rights reserved.

import Cocoa

class AccountsListViewController: NSViewController {

    private let agent = Agent.shared
    private let walletsManager = WalletsManager.shared
    private var cellModels = [CellModel]()
    
    var onSelectedWallet: ((InkWallet) -> Void)?
    var newWalletId: String?
    
    enum CellModel {
        case wallet
        case addAccountOption(AddAccountOption)
    }
    
    enum AddAccountOption {
        case createNew, importExisting
        
        var title: String {
            switch self {
            case .createNew:
                return "🌱  Create New"
            case .importExisting:
                return "💼  Import Existing"
            }
        }
    }
    
    @IBOutlet weak var addButton: NSButton! {
        didSet {
            let menu = NSMenu()
            addButton.menu = menu
            menu.delegate = self
        }
    }
    
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var tableView: RightClickTableView! {
        didSet {
            tableView.delegate = self
            tableView.dataSource = self
        }
    }
    
    private var wallets: [InkWallet] {
        return walletsManager.wallets
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupAccountsMenu()
        reloadTitle()
        updateCellModels()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        blinkNewWalletCellIfNeeded()
    }
    
    private func setupAccountsMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Copy address", action: #selector(didClickCopyAddress(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "View on Zerion", action: #selector(didClickViewOnZerion(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show account key", action: #selector(didClickExportAccount(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Remove account", action: #selector(didClickRemoveAccount(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "How to WalletConnect?", action: #selector(showInstructionsAlert), keyEquivalent: ""))
        tableView.menu = menu
    }
    
    private func reloadTitle() {
        titleLabel.stringValue = onSelectedWallet != nil && !wallets.isEmpty ? "Select\nAccount" : "Accounts"
        addButton.isHidden = wallets.isEmpty
    }
    
    @objc private func didBecomeActive() {
        guard view.window?.isVisible == true else { return }
        if let completion = agent.getWalletSelectionCompletionIfShouldSelect() {
            onSelectedWallet = completion
        }
        reloadTitle()
    }
    
    @IBAction func addButtonTapped(_ sender: NSButton) {
        let menu = sender.menu
        
        let createItem = NSMenuItem(title: "", action: #selector(didClickCreateAccount), keyEquivalent: "")
        let importItem = NSMenuItem(title: "", action: #selector(didClickImportAccount), keyEquivalent: "")
        let font = NSFont.systemFont(ofSize: 21, weight: .bold)
        createItem.attributedTitle = NSAttributedString(string: AddAccountOption.createNew.title, attributes: [.font: font])
        importItem.attributedTitle = NSAttributedString(string: AddAccountOption.importExisting.title, attributes: [.font: font])
        menu?.addItem(createItem)
        menu?.addItem(importItem)
        
        var origin = sender.frame.origin
        origin.x += sender.frame.width
        origin.y += sender.frame.height
        menu?.popUp(positioning: nil, at: origin, in: view)
    }
    
    @objc private func didClickCreateAccount() {
        let wallet = try? walletsManager.createWallet()
        newWalletId = wallet?.id
        reloadTitle()
        updateCellModels()
        tableView.reloadData()
        blinkNewWalletCellIfNeeded()
        // TODO: show backup phrase
    }
    
    private func blinkNewWalletCellIfNeeded() {
        guard let id = newWalletId else { return }
        newWalletId = nil
        guard let row = wallets.firstIndex(where: { $0.id == id }), row < cellModels.count else { return }
        tableView.scrollRowToVisible(row)
        (tableView.rowView(atRow: row, makeIfNecessary: true) as? AccountCellView)?.blink()
    }
    
    @objc private func didClickImportAccount() {
        let importViewController = instantiate(ImportViewController.self)
        importViewController.onSelectedWallet = onSelectedWallet
        view.window?.contentViewController = importViewController
    }
    
    @objc private func didClickViewOnZerion(_ sender: AnyObject) {
        let row = tableView.deselectedRow
        guard row >= 0, let address = wallets[row].ethereumAddress else { return }
        if let url = URL(string: "https://app.zerion.io/\(address)/overview") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func didClickCopyAddress(_ sender: AnyObject) {
        let row = tableView.deselectedRow
        guard row >= 0, let address = wallets[row].ethereumAddress else { return }
        NSPasteboard.general.clearAndSetString(address)
    }

    @objc private func didClickRemoveAccount(_ sender: AnyObject) {
        let row = tableView.deselectedRow
        guard row >= 0 else { return }
        let alert = Alert()
        alert.messageText = "Removed accounts can't be recovered."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Remove anyway")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            agent.askAuthentication(on: view.window, getBackTo: self, onStart: false, reason: .removeAccount) { [weak self] allowed in
                Window.activateWindow(self?.view.window)
                if allowed {
                    self?.removeAccountAtIndex(row)
                }
            }
        }
    }
    
    @objc private func didClickExportAccount(_ sender: AnyObject) {
        let row = tableView.deselectedRow
        guard row >= 0 else { return }
        let isMnemonic = wallets[row].isMnemonic
        let alert = Alert()
        
        alert.messageText = "\(isMnemonic ? "Secret words give" : "Private key gives") full access to your funds."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "I understand the risks")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let reason: AuthenticationReason = isMnemonic ? .showSecretWords : .showPrivateKey
            agent.askAuthentication(on: view.window, getBackTo: self, onStart: false, reason: reason) { [weak self] allowed in
                Window.activateWindow(self?.view.window)
                if allowed {
                    self?.showKey(index: row, mnemonic: isMnemonic)
                }
            }
        }
    }
    
    private func showKey(index: Int, mnemonic: Bool) {
        let wallet = wallets[index]
        
        let secret: String
        if mnemonic, let mnemonicString = try? walletsManager.exportMnemonic(wallet: wallet) {
            secret = mnemonicString
        } else if let data = try? walletsManager.exportPrivateKey(wallet: wallet) {
            secret = data.hexString
        } else {
            return
        }
        
        let alert = Alert()
        alert.messageText = mnemonic ? "Secret words" : "Private key"
        alert.informativeText = secret
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        if alert.runModal() != .alertFirstButtonReturn {
            NSPasteboard.general.clearAndSetString(secret)
        }
    }
    
    @objc private func showInstructionsAlert() {
        Alert.showWalletConnectInstructions()
    }
    
    private func removeAccountAtIndex(_ index: Int) {
        let wallet = wallets[index]
        try? walletsManager.delete(wallet: wallet)
        reloadTitle()
        updateCellModels()
        tableView.reloadData()
    }
    
    private func updateCellModels() {
        if wallets.isEmpty {
            cellModels = [.addAccountOption(.createNew), .addAccountOption(.importExisting)]
            tableView.shouldShowRightClickMenu = false
        } else {
            cellModels = Array(repeating: CellModel.wallet, count: wallets.count)
            tableView.shouldShowRightClickMenu = true
        }
    }
    
}

extension AccountsListViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView.selectedRow < 0 else { return false }
        let model = cellModels[row]
        
        switch model {
        case .wallet:
            let wallet = wallets[row]
            if let onSelectedWallet = onSelectedWallet {
                onSelectedWallet(wallet)
            } else {
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { [weak self] _ in
                    var point = NSEvent.mouseLocation
                    point.x += 1
                    self?.tableView.menu?.popUp(positioning: nil, at: point, in: nil)
                }
            }
            return true
        case let .addAccountOption(addAccountOption):
            switch addAccountOption {
            case .createNew:
                didClickCreateAccount()
            case .importExisting:
                didClickImportAccount()
            }
            return false
        }
    }
    
}

extension AccountsListViewController: NSTableViewDataSource {
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let model = cellModels[row]
        switch model {
        case .wallet:
            let wallet = wallets[row]
            let rowView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("AccountCellView"), owner: self) as? AccountCellView
            rowView?.setup(address: wallet.ethereumAddress ?? "")
            return rowView
        case let .addAccountOption(addAccountOption):
            let rowView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("AddAccountOptionCellView"), owner: self) as? AddAccountOptionCellView
            rowView?.setup(title: addAccountOption.title)
            return rowView
        }
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .wallet = cellModels[row] {
            return 50
        } else {
            return 44
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return cellModels.count
    }
    
}

extension AccountsListViewController: NSMenuDelegate {
    
    func menuDidClose(_ menu: NSMenu) {
        if menu === addButton.menu {
            menu.removeAllItems()
        } else {
            tableView.deselectedRow = tableView.selectedRow
            tableView.deselectAll(nil)
        }
    }
    
}

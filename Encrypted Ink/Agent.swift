// Copyright © 2021 Encrypted Ink. All rights reserved.

import Cocoa
import WalletConnect
import LocalAuthentication

class Agent {

    static let shared = Agent()
    private lazy var statusImage = NSImage(named: "Status")
    
    private init() {}
    private var statusBarItem: NSStatusItem!
    
    func start() {
        checkPasteboardAndOpen(onAppStart: true)
    }
    
    func reopen() {
        checkPasteboardAndOpen(onAppStart: false)
    }
    
    func showInitialScreen(onAppStart: Bool, wcSession: WCSession?) {
        let windowController: NSWindowController
        if onAppStart, let currentWindowController = Window.current {
            windowController = currentWindowController
            Window.activate(windowController)
        } else {
            windowController = Window.showNew()
        }
        
        let completion = onSelectedAccount(session: wcSession)
        let accounts = AccountsService.getAccounts()
        if !accounts.isEmpty {
            let accountsList = AccountsListViewController.with(preloadedAccounts: accounts)
            accountsList.onSelectedAccount = completion
            windowController.contentViewController = accountsList
        } else {
            let importViewController = instantiate(ImportViewController.self)
            importViewController.onSelectedAccount = completion
            windowController.contentViewController = importViewController
        }
    }
    
    func showApprove(title: String, meta: String, completion: @escaping (Bool) -> Void) {
        let windowController = Window.showNew()
        let approveViewController = ApproveViewController.with(title: title, meta: meta) { [weak self] result in
            Window.closeAll()
            Window.activateBrowser()
            if result {
                self?.proceedAfterAuthentication(reason: title, completion: completion)
            } else {
                completion(result)
            }
        }
        windowController.contentViewController = approveViewController
    }
    
    func showErrorMessage(_ message: String) {
        let windowController = Window.showNew()
        windowController.contentViewController = ErrorViewController.withMessage(message)
    }
    
    func setupStatusBarItem() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = statusImage
        statusBarItem.button?.target = self
        statusBarItem.button?.action = #selector(statusBarButtonClicked(sender:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp])
    }
    
    func processInputLink(_ link: String) {
        let session = sessionWithLink(link)
        showInitialScreen(onAppStart: false, wcSession: session)
    }
    
    func getAccountSelectionCompletionIfShouldSelect() -> ((Account) -> Void)? {
        let session = getSessionFromPasteboard()
        return onSelectedAccount(session: session)
    }
    
    private func onSelectedAccount(session: WCSession?) -> ((Account) -> Void)? {
        guard let session = session else { return nil }
        return { [weak self] account in
            self?.connectWallet(session: session, account: account)
        }
    }
    
    private func getSessionFromPasteboard() -> WCSession? {
        let pasteboard = NSPasteboard.general
        let link = pasteboard.string(forType: .string) ?? ""
        let session = sessionWithLink(link)
        if session != nil {
            pasteboard.clearContents()
        }
        return session
    }
    
    private func checkPasteboardAndOpen(onAppStart: Bool) {
        let session = getSessionFromPasteboard()
        showInitialScreen(onAppStart: onAppStart, wcSession: session)
    }
    
    private func sessionWithLink(_ link: String) -> WCSession? {
        return WalletConnect.shared.sessionWithLink(link)
    }
    
    @objc private func statusBarButtonClicked(sender: NSStatusBarButton) {
        checkPasteboardAndOpen(onAppStart: false)
    }
    
    func proceedAfterAuthentication(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true)
            return
        }
        
        context.localizedCancelTitle = "Cancel"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason ) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    private func connectWallet(session: WCSession, account: Account) {
        WalletConnect.shared.connect(session: session, address: account.address) { [weak self] connected in
            if connected {
                Window.closeAll()
                Window.activateBrowser()
            } else {
                self?.showErrorMessage("Failed to connect")
            }
        }
        
        let windowController = Window.showNew()
        windowController.contentViewController = WaitingViewController.withReason("Connecting")
    }
    
}

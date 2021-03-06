//
//  StatusesViewController.swift
//  Tusk
//
//  Created by Patrick Perini on 8/10/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import UIKit
import ReSwift
import MastodonKit
import SafariServices

class StatusesViewController: PaginatingTableViewController<Status> {
    var initialLastSeenID: String? = nil
    var statuses: [Status] = []
    var unsuppressedStatusIDs: [String] = []
    
    lazy private var mergeHandler: TableViewMergeHandler<Status> = TableViewMergeHandler(tableView: self.tableView,
                                                                                              section: self.statusesSection,
                                                                                              dataComparator: self.statusesAreEqual)
    
    var nextPageAction: () -> Action? = { nil }
    var previousPageAction: () -> Action? = { nil }
    var reloadAction: (String?) -> Action? = { (_) in nil } {
        didSet {
            self.pollStatuses(pageDirection: .Reload(from: self.initialLastSeenID))
        }
    }
    
    var statusesSection: Int { return 0 }
    var numberOfStatusRows: Int { return self.statuses.count + (self.selectedStatusIndex == nil ? 0 : 1) }
    override var topIndexPath: IndexPath { return IndexPath(row: 0, section: self.statusesSection) }
    
    var didUpdateLastSeenData: ((Status) -> Void)? = nil
    
    private var selectedStatusIndex: Int? = nil {
        didSet {
            guard let tableView = self.tableView as? TableView else { return }
            tableView.appendBatchUpdates({
                if let oldValue = oldValue {
                    UIView.perform(animated: tableView.indexPathsForVisibleRows?.map({ $0.row }).contains(oldValue) ?? false) {
                        tableView.deselectRow(at: IndexPath(row: oldValue, section: self.statusesSection), animated: true)
                        tableView.deleteRows(at: [IndexPath(row: oldValue + 1, section: self.statusesSection)], with: .none)
                    }
                }
                
                if let selectedIndex = self.selectedStatusIndex {
                    tableView.insertRows(at: [IndexPath(row: selectedIndex + 1, section: self.statusesSection)], with: .none)
                }
            })
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.tableView.visibleCells.forEach { (cell) in
            (cell as? StatusViewCell)?.hideSwipe(animated: true)
        }
    }
    
    func pollStatuses(pageDirection: PageDirection = .Reload(from: nil)) {
        let possibleAction: Action?
        switch pageDirection {
        case .NextPage: possibleAction = self.nextPageAction()
        case .PreviousPage: possibleAction = self.previousPageAction()
        case .Reload(let from): possibleAction = self.reloadAction(from)
        }
        
        guard let action = possibleAction else { return }
        GlobalStore.dispatch(action)
    }
    
    func updateStatuses(statuses: [Status]) {
        self.endRefreshing()
        self.endPaginating()
        
        self.statuses = statuses
        self.mergeHandler.mergeData(data: statuses)
        
        self.updateUnreadIndicator()
    }
    
    // MARK: Table View
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.numberOfStatusRows
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let statusIndex = self.statusIndexForIndexPath(indexPath: indexPath)
        if (statusIndex == NSNotFound) { // Action Cell
            return StatusActionViewCell.CellHeight
        }
        
        let status = self.statuses[statusIndex]
        return self.mergeHandler.heightForCellWithData(data: status,
                                                            nibName: "StatusViewCell",
                                                            configurator: self.statusCellConfiguration(status: status))
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let statusIndex = self.statusIndexForIndexPath(indexPath: indexPath)
        if (statusIndex == NSNotFound) { // Action Cell
            let statusIndex = indexPath.row - 1
            let status = self.statuses[statusIndex]
            let displayStatus = status.reblog ?? status
            
            let cell: StatusActionViewCell = self.tableView.dequeueReusableCell(withIdentifier: "Action",
                                                                                for: indexPath,
                                                                                usingNibNamed: "StatusActionViewCell")
            
            cell.replyButtonWasTapped = {
                self.selectedStatusIndex = nil
                self.performSegue(withIdentifier: "PresentComposeViewController", sender: ("reply", displayStatus))
            }
            
            cell.favouriteButton.isSelected = displayStatus.favourited ?? false
            cell.favouritedButtonWasTapped = {
                guard let client = GlobalStore.state.auth.client else { return }
                cell.favouriteButton.isSelected = !cell.favouriteButton.isSelected
                GlobalStore.dispatch(StatusUpdateState.ToggleFavourite(client: client, id: StatusUpdateState.updateID(), status: displayStatus))
            }
            
            cell.reblogButton.isSelected = displayStatus.reblogged ?? false
            cell.reblogButtonWasTapped = {
                guard let client = GlobalStore.state.auth.client else { return }
                cell.reblogButton.isSelected = !cell.reblogButton.isSelected
                GlobalStore.dispatch(StatusUpdateState.ToggleReblog(client: client, id: StatusUpdateState.updateID(), status: displayStatus))
            }
            
            cell.settingsButtonWasTapped = { self.presentSettings(status: displayStatus) }
            
            return cell
        }
        
        let cell: StatusViewCell = self.tableView.dequeueReusableCell(withIdentifier: "Status",
                                                                      for: indexPath,
                                                                      usingNibNamed: "StatusViewCell")
        let status = self.statuses[statusIndex]
        self.statusCellConfiguration(status: status, indexPath: indexPath)(cell)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let selectedStatusIndex = self.selectedStatusIndex else { return indexPath }
        return indexPath.row != selectedStatusIndex + 1 ? indexPath : nil
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var statusIndex: Int? = self.statusIndexForIndexPath(indexPath: indexPath)
        if (statusIndex == self.selectedStatusIndex) { statusIndex = nil }
        
        self.mergeHandler.selectedElement = nil
        if let statusIndex = statusIndex {
            self.mergeHandler.selectedElement = self.statuses[statusIndex]
        }
        
        self.selectedStatusIndex = nil
        self.selectedStatusIndex = statusIndex
    }
    
    override func tableView(tableView: UITableView, didUpdateLastSeenData data: Status) {
        // Find one above, since API requests are exclusive sets
        let status: Status
        if let index = self.statuses.index(of: data),
            index > 0 {
            status = self.statuses[index - 1]
        } else {
            status = data
        }
        
        self.didUpdateLastSeenData?(status)
    }
    
    override func dataForRowAtIndexPath(indexPath: IndexPath) -> Status? {
        let index = self.statusIndexForIndexPath(indexPath: indexPath)
        guard index != NSNotFound, !self.statuses.isEmpty, index < self.statuses.count else { return nil }
        return self.statuses[index]
    }
    
    private func statusIndexForIndexPath(indexPath: IndexPath) -> Int {
        guard let selectedIndex = self.selectedStatusIndex, selectedIndex < indexPath.row else { return indexPath.row }
        if (indexPath.row == selectedIndex + 1) { return NSNotFound }
        return indexPath.row - 1
    }
    
    private func statusCellConfiguration(status: Status, indexPath: IndexPath? = nil) -> (StatusViewCell) -> Void {
        return { (cell) in
            let displayStatus = status.reblog ?? status
            
            cell.originalStatus = nil
            if (status != displayStatus) {
                cell.originalStatus = status
            }
            
            cell.isSupressingContent = (
                displayStatus.warning != nil &&
                    !self.unsuppressedStatusIDs.contains(status.id) &&
                    GlobalStore.state.storedDefaults.hideContentWarnings
            )
            
            if let indexPath = indexPath { // Only enable visible responders
                cell.attachmentWasTapped = ModalHandler.handleAttachmentForViewController(viewController: self, status: displayStatus)
                cell.accountElementWasTapped = { (account) in
                    self.pushToAccount(account: account)
                }
                cell.linkWasTapped = ModalHandler.handleLinkForViewController(viewController: self)
                cell.contextPushWasTriggered = { (status) in
                    self.pushToContext(status: status)
                }
                cell.contentShouldReveal = { (shouldReveal) in
                    if (shouldReveal) {
                        if (self.unsuppressedStatusIDs.contains(status.id)) { return }
                        GlobalStore.dispatch(StoredDefaultsState.AddUnsuppressedStatusID(value: status.id))
                    } else {
                        if (!self.unsuppressedStatusIDs.contains(status.id)) { return }
                        GlobalStore.dispatch(StoredDefaultsState.RemoveUnsuppressedStatusID(value: status.id))
                    }
                    
                    guard let tableView = self.tableView as? TableView else { return }
                    self.mergeHandler.invalidateHeightForCellWithData(data: status)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        tableView.appendBatchUpdates({
                            tableView.reloadRows(at: [indexPath], with: .none)
                        })
                    }
                }
            }
            
            cell.status = displayStatus
        }
    }
    
    private func statusesAreEqual(lhs: Status, rhs: Status) -> Bool {
        return (
            lhs.id == rhs.id &&
            lhs.favourited == rhs.favourited &&
            lhs.reblogged == rhs.reblogged &&
            lhs.reblog?.favourited == rhs.reblog?.favourited &&
            lhs.reblog?.reblogged == rhs.reblog?.reblogged
        )
    }
    
    // MARK: Paging
    override func refreshControlBeganRefreshing() {
        guard self.refreshingEnabled else { return }
        super.refreshControlBeganRefreshing()
        self.pollStatuses(pageDirection: .PreviousPage)
    }
    
    override func pageControlBeganRefreshing() {
        guard self.pagingEnabled else { return }
        super.pageControlBeganRefreshing()
        self.pollStatuses(pageDirection: .NextPage)
    }
    
    // MARK: Navigation
    func openURL(url: URL) {
        let safari = SFSafariViewController(url: url)
        self.present(safari, animated: true, completion: nil)
    }
    
    func pushToAccount(account: AccountType) {
        self.performSegue(withIdentifier: "PushAccountViewController", sender: account)
        
        guard let client = GlobalStore.state.auth.client else { return }
        GlobalStore.dispatch(AccountState.PollAccount(client: client, account: account))
    }
    
    func pushToContext(status: Status) {
        self.performSegue(withIdentifier: "PushContextViewController", sender: status)
        
        guard let client = GlobalStore.state.auth.client else { return }
        GlobalStore.dispatch(ContextState.PollContext(client: client, status: status))
    }
    
    func presentSettings(status: Status) {
        guard let client = GlobalStore.state.auth.client else { return }
        
        let optionsPicker = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        optionsPicker.addAction(UIAlertAction(title: "Share", style: .default, handler: { (_) in
            self.presentShareSheet(status: status)
        }))
        
        if (status.account == GlobalStore.state.accounts.activeAccount?.account as? Account) {
            let deleteHandler = {
                self.selectedStatusIndex = nil
                GlobalStore.dispatch(StatusUpdateState.DeleteStatus(client: client,
                                                                    id: StatusUpdateState.updateID(),
                                                                    status: status))
            }
            
            optionsPicker.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { (_) in deleteHandler() }))
            optionsPicker.addAction(UIAlertAction(title: "Redraft", style: .destructive, handler: { (_) in
                deleteHandler()
                self.performSegue(withIdentifier: "PresentComposeViewController", sender: ("redraft", status))
            }))
        } else {
            optionsPicker.addAction(UIAlertAction(title: "Report", style: .destructive, handler: { (_) in
                let confirmAlert = UIAlertController(title: "Report this user and post as offensive?",
                                                     message: nil,
                                                     preferredStyle: .alert)
                confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                confirmAlert.addAction(UIAlertAction(title: "Report", style: .destructive, handler: { (_) in
                    self.selectedStatusIndex = nil
                    GlobalStore.dispatch(StatusUpdateState.ReportStatus(client: client,
                                                                        id: StatusUpdateState.updateID(),
                                                                        status: status))
                }))
                
                self.present(confirmAlert, animated: true, completion: nil)
            }))
        }
        
        optionsPicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(optionsPicker, animated: true, completion: nil)
    }
    
    func presentShareSheet(status: Status) {
        let shareSheet = UIActivityViewController(activityItems: [
            status.sharableString,
            status.url as Any
        ], applicationActivities: [
            CopyLinkActivity()
        ])
        
        self.present(shareSheet, animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier {
        case "PushAccountViewController": do {
            let sentAccount: AccountType? = (sender as? Account) ?? (sender as? AccountPlaceholder)
            guard let accountVC = segue.destination as? AccountViewController, let account = sentAccount else {
                segue.destination.dismiss(animated: true, completion: nil)
                return
            }
            
            accountVC.account = account
            }
        case "PushContextViewController": do {
            guard let contextVC = segue.destination as? ContextViewController, let status = sender as? Status else {
                segue.destination.dismiss(animated: true, completion: nil)
                return
            }
            
            contextVC.status = status
            }
        case "PresentComposeViewController": do {
            guard let container = segue.destination as? ComposeContainerViewController,
                let composeVC = container.composeViewController,
                let action = sender as? (String, Status) else { return }
            if (action.0 == "reply") {
                composeVC.inReplyTo = action.1
            } else if (action.0 == "redraft") {
                composeVC.redraft = action.1
            }
            }
        default: return
        }
    }
}


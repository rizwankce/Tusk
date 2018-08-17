//
//  NotificationsViewController.swift
//  Tusk
//
//  Created by Patrick Perini on 8/10/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import UIKit
import ReSwift
import MastodonKit
import SafariServices

class NotificationsViewController: PaginatingTableViewController, StoreSubscriber {
    typealias StoreSubscriberStateType = NotificationsState

    var notifications: [MKNotification] = []
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        GlobalStore.subscribe(self) { (subscription) in subscription.select { (state) in state.notifications } }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.pollNotifications()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        GlobalStore.unsubscribe(self)
    }
    
    func pollNotifications(pageDirection: PageDirection = .Reload) {
        guard let client = GlobalStore.state.auth.client else { return }
        let action: Action
        switch pageDirection {
        case .NextPage: action = NotificationsState.PollOlderNotifications(client: client)
        case .PreviousPage: action = NotificationsState.PollNewerNotifications(client: client)
        case .Reload: action = NotificationsState.PollNotifications(client: client)
        }
        
        GlobalStore.dispatch(action)
    }
    
    func newState(state: NotificationsState) {
        if (!state.notifications.isEmpty && state.notifications[0].createdAt != state.lastRead) {
            GlobalStore.dispatch(NotificationsState.SetLastReadDate(value: state.notifications[0].createdAt))
        }
        
        DispatchQueue.main.async {
            if (self.notifications != state.notifications) {
                self.notifications = state.notifications
                self.tableView.reloadData()
            }
            
            self.endRefreshing()
            self.endPaginating()
        }
    }
    
    // UITableViewDataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.notifications.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: "Notification") as? NotificationViewCell else {
            self.tableView.register(UINib(nibName: "NotificationViewCell", bundle: nil), forCellReuseIdentifier: "Notification")
            return self.tableView(tableView, cellForRowAt: indexPath)
        }
        
        let notification = self.notifications[indexPath.row]
        cell.notification = notification
        cell.avatarWasTapped = { self.pushToAccount(account: notification.account) }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let notification = self.notifications[indexPath.row]
        let url = notification.status?.url ?? URL(string: notification.account.url)!
        
        self.pushToURL(url: url)
    }
    
    // Paging
    override func refreshControlBeganRefreshing() {
        super.refreshControlBeganRefreshing()
        self.pollNotifications(pageDirection: .PreviousPage)
    }
    
    override func pageControlBeganRefreshing() {
        super.pageControlBeganRefreshing()
        self.pollNotifications(pageDirection: .NextPage)
    }
    
    // Navigation
    func pushToURL(url: URL) {
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.navigationItem.title = "Mastodon"
        safariViewController.hidesBottomBarWhenPushed = true
        safariViewController.script
        
        self.navigationController?.pushViewController(safariViewController, animated: true)
    }
    
    func pushToAccount(account: Account) {
        self.performSegue(withIdentifier: "PushAccountViewController", sender: account)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier {
        case "PushAccountViewController": do {
            guard let accountVC = segue.destination as? AccountViewController, let account = sender as? Account else {
                segue.destination.dismiss(animated: true, completion: nil)
                return
            }
            
            accountVC.account = account
            }
        default: return
        }
    }
}


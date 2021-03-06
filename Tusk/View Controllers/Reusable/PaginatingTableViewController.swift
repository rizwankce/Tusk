//
//  PaginatingTableViewController.swift
//  Tusk
//
//  Created by Patrick Perini on 8/12/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import UIKit
import MastodonKit

enum PageDirection {
    case NextPage
    case PreviousPage
    case Reload(from: String?)
}

class PaginatingTableViewController<DataType: Comparable>: UITableViewController {
    private let paginationActivityIndicatorSize: CGFloat = 44.0
    var paginationActivityIndicator: UIActivityIndicatorView!
    
    var pagingEnabled: Bool = true { didSet { self.reloadActivityIndicators() } }
    var refreshingEnabled: Bool = true { didSet { self.reloadActivityIndicators() } }
    
    var topIndexPath: IndexPath { return IndexPath(row: 0, section: 0) }

    private var state: State = .Resting
    private lazy var topSeenData: DataType? = self.dataForRowAtIndexPath(indexPath: self.topIndexPath)
    var navBar: NavigationBar? {
        return self.navigationController?.navigationBar as? NavigationBar
    }
    
    private enum State {
        case Refreshing
        case Paging
        case Resting
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.reloadActivityIndicators()
    }
    
    private func reloadActivityIndicators() {
        self.refreshControl = nil
        if self.refreshingEnabled {
            self.refreshControl = UIRefreshControl()
            self.refreshControl?.addTarget(self, action: #selector(_refreshControlBeganRefreshing), for: .allEvents)
        }
    
        self.paginationActivityIndicator?.removeFromSuperview()
        
        if self.pagingEnabled {
            let size = self.paginationActivityIndicatorSize
            let paginateView = UIView(frame: CGRect(x: 0.0, y: 0.0,
                                                    width: self.tableView.frame.width,
                                                    height: size))
        
            let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
            activityIndicator.frame = CGRect(x: (self.tableView.frame.width - size) / 2,
                                             y: 0,
                                             width: size,
                                             height: size)
            activityIndicator.hidesWhenStopped = true
            activityIndicator.startAnimating()
            paginateView.addSubview(activityIndicator)
        
            self.paginationActivityIndicator = activityIndicator
            self.tableView.tableFooterView = paginateView
        }
    }

    @objc private func _refreshControlBeganRefreshing() {
        self.state = .Refreshing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            self.refreshControlBeganRefreshing()
        }
    }
    
    func refreshControlBeganRefreshing() {
        self.refreshControl?.endRefreshing()
    }
    
    func endRefreshing() {
        guard self.state == .Refreshing else { return }
        self.state = .Resting
        self.refreshControl?.endRefreshing()
    }
    
    func pageControlBeganRefreshing() {
        self.state = .Paging
    }
    
    func endPaginating() {
        guard self.state == .Paging else { return }
        self.state = .Resting
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if (!decelerate) {
            self.scrollViewDidEndDecelerating(scrollView)
        }
    }
    
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let indicatorFrame = self.paginationActivityIndicator.convert(self.paginationActivityIndicator.frame, to: scrollView)
        if (indicatorFrame.intersects(scrollView.bounds)) {
            self.pageControlBeganRefreshing()
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard self.state == .Resting,
                let topIndex = self.tableView.fullyVisibleIndexPaths().first,
                let topData = self.dataForRowAtIndexPath(indexPath: topIndex) else { return }
            guard let topSeen = self.topSeenData else {
                self.topSeenData = topData
                return
            }
        
            self.tableView(tableView: self.tableView, didUpdateLastSeenData: topData)
            
            self.topSeenData = max(topData, topSeen)
            self.updateUnreadIndicator()
        }
    }
    
    func tableView(tableView: UITableView, didUpdateLastSeenData data: DataType) {
    }
    
    func dataForRowAtIndexPath(indexPath: IndexPath) -> DataType? {
        fatalError("dataForRowAtIndexPath(indexPath:) has no valid abstract implementation")
    }
    
    func updateUnreadIndicator() {
        guard let data = self.dataForRowAtIndexPath(indexPath: self.topIndexPath),
            let lastSeen = self.topSeenData else { return }
        self.navBar?.setShadowHidden(hidden: data <= lastSeen,
                                     animated: true)
    }
}

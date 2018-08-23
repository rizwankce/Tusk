//
//  PaginatingTableViewController.swift
//  Tusk
//
//  Created by Patrick Perini on 8/12/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import UIKit

enum PageDirection {
    case NextPage
    case PreviousPage
    case Reload
}

class PaginatingTableViewController: UITableViewController {
    private static let paginationActivityIndicatorSize: CGFloat = 44.0
    var paginationActivityIndicator: UIActivityIndicatorView!

    private var state: State = .Resting
    
    private enum State {
        case Refreshing
        case Paging
        case Resting
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.refreshControl = UIRefreshControl()
        self.refreshControl?.addTarget(self, action: #selector(_refreshControlBeganRefreshing), for: .allEvents)
        
        let size = PaginatingTableViewController.paginationActivityIndicatorSize
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
        }
    }
}

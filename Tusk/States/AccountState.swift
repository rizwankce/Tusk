//
//  AccountState.swift
//  Tusk
//
//  Created by Patrick Perini on 8/21/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import MastodonKit
import ReSwift

protocol AccountAction: Action { var account: Account { get } }
protocol AccountPollingAction: AccountAction, PollAction {}

struct AccountState: StateType, StatusViewableState {
    private struct SetAccount: AccountAction { let account: Account; let active: Bool }
    struct SetPinnedStatuses: AccountAction { let value: [Status]; let account: Account }
    
    struct SetFollowing: AccountAction { let value: [Account]; let account: Account }
    struct SetFollowingPage: AccountAction { let value: Pagination?; let account: Account }

    struct SetFollowers: AccountAction { let value: [Account]; let account: Account }
    private struct SetFollowersPage: AccountAction { let value: Pagination?; let account: Account }
    
    struct SetStatuses: AccountAction { let value: [Status]; let account: Account }
    private struct SetStatusesPage: AccountAction { let value: Pagination?; let account: Account }
    
    struct PollAccount: Action { let client: Client; let account: Account? }
    struct PollPinnedStatuses: AccountAction { let client: Client; let account: Account }
    
    struct PollFollowing: AccountAction { let client: Client; let account: Account }
    struct PollOlderFollowing: AccountPollingAction { let client: Client; let account: Account }
    struct PollNewerFollowing: AccountPollingAction { let client: Client; let account: Account }
    
    struct PollFollowers: AccountAction { let client: Client; let account: Account }
    struct PollOlderFollowers: AccountPollingAction { let client: Client; let account: Account }
    struct PollNewerFollowers: AccountPollingAction { let client: Client; let account: Account }
    
    struct PollStatuses: AccountPollingAction { let client: Client; let account: Account }
    struct PollOlderStatuses: AccountPollingAction { let client: Client; let account: Account }
    struct PollNewerStatuses: AccountPollingAction { let client: Client; let account: Account }
    
    var isActiveAccount: Bool = false
    var account: Account? = nil
    var pinnedStatuses: [Status] = []
    var following: [Account] = []
    var followers: [Account] = []
    var statuses: [Status] = []
    
    private var statusesNextPage: RequestRange? = nil
    private var statusesPreviousPage: RequestRange? = nil
    private lazy var statusesPaginatableData: PaginatingData<Status, Status> = PaginatingData<Status, Status>(provider: self.statusesProvider)
    
    private var followersNextPage: RequestRange? = nil
    private var followersPreviousPage: RequestRange? = nil
    private lazy var followersPaginatableData: PaginatingData<Account, Account> = PaginatingData<Account, Account>(provider: self.followersProvider)
    
    private var followingNextPage: RequestRange? = nil
    private var followingPreviousPage: RequestRange? = nil
    private lazy var followingPaginatableData: PaginatingData<Account, Account> = PaginatingData<Account, Account>(provider: self.followingProvider)
    
    var hashableValue: Int { return (self.account?.hashValue ?? 0) + (self.isActiveAccount ? 1 : 0) }
    
    static func reducer(action: Action, state: AccountState?) -> AccountState {
        var state = state ?? AccountState()
        
        switch action {
        case let action as PollAccount: do {
            pollAccount(client: action.client, accountID: action.account?.id)
            state = AccountState()
            state.account = action.account
            state.isActiveAccount = action.account?.id == nil
            return state
            }
        default: break
        }
        
        guard let action = action as? AccountAction, state.account == nil || state.account == action.account else { return state }
        
        switch action {
        case let action as SetAccount: do {
            state.account = action.account
            state.isActiveAccount = action.active
            }
        case let action as SetPinnedStatuses: state.pinnedStatuses = action.value
            
        case let action as SetFollowing: state.following = action.value
        case let action as SetFollowingPage: (state.followingNextPage, state.followingPreviousPage) = state.followingUpdatedPages(pagination: action.value)
            
        case let action as SetFollowers: state.followers = action.value
        case let action as SetFollowersPage: (state.followersNextPage, state.followersPreviousPage) = state.followersUpdatedPages(pagination: action.value)
            
        case let action as SetStatuses: state.statuses = action.value
        case let action as SetStatusesPage: (state.statusesNextPage, state.statusesPreviousPage) = state.statusesUpdatedPages(pagination: action.value)
        case let action as PollPinnedStatuses: state.pollPinnedStatuses(client: action.client)
            
        case let action as PollFollowing: state.pollFollowing(client: action.client, account: action.account)
        case let action as PollOlderFollowing: state.pollFollowing(client: action.client, account: action.account, range: state.followingNextPage)
        case let action as PollNewerFollowing: state.pollFollowing(client: action.client, account: action.account, range: state.followingPreviousPage)
            
        case let action as PollStatuses: state.pollStatuses(client: action.client, account: action.account)
        case let action as PollOlderStatuses: state.pollStatuses(client: action.client, account: action.account, range: state.statusesNextPage)
        case let action as PollNewerStatuses: state.pollStatuses(client: action.client, account: action.account, range: state.statusesPreviousPage)
            
        case let action as PollFollowers: state.pollFollowers(client: action.client, account: action.account)
        case let action as PollOlderFollowers: state.pollFollowers(client: action.client, account: action.account, range: state.followersNextPage)
        case let action as PollNewerFollowers: state.pollFollowers(client: action.client, account: action.account, range: state.followersPreviousPage)
        default: break
        }
        
        return state
    }
    
    static func pollAccount(client: Client, accountID: String? = nil) {
        let request = accountID == nil ? Accounts.currentUser() : Accounts.account(id: accountID!)
        client.run(request) { (result) in
            switch result {
            case .success(let account, _): do {
                GlobalStore.dispatch(SetAccount(account: account, active: accountID == nil))
                GlobalStore.dispatch(PollPinnedStatuses(client: client, account: account))
                GlobalStore.dispatch(PollFollowing(client: client, account: account))
                print("success", #file, #line)
                }
            case .failure(let error): print(error, #file, #line)
            }
        }
    }
    
    func pollPinnedStatuses(client: Client) {
        guard let account = self.account else { return }
        let request = Accounts.statuses(id: account.id,
                                        mediaOnly: false,
                                        pinnedOnly: true,
                                        excludeReplies: true,
                                        range: .limit(40))
        client.run(request) { (result) in
            switch result {
            case .success(let statuses, _): do {
                GlobalStore.dispatch(SetPinnedStatuses(value: statuses, account: account))
                print("success", #file, #line)
                }
            case .failure(let error): print(error, #file, #line)
            }
        }
    }
    
    mutating func pollStatuses(client: Client, account: Account, range: RequestRange? = nil) {
        self.statusesPaginatableData.pollData(client: client, range: range, existingData: self.statuses, filters: []) { (
            statuses: [Status],
            pagination: Pagination?
        ) in
            GlobalStore.dispatch(SetStatuses(value: statuses, account: account))
            GlobalStore.dispatch(SetStatusesPage(value: pagination, account: account))
        }
    }
    
    func statusesProvider(range: RequestRange?) -> Request<[Status]> {
        guard let account = self.account else { fatalError("Cannot request statuses for nil account") }
        guard let range = range else { return Accounts.statuses(id: account.id) }
        return Accounts.statuses(id: account.id, range: range)
    }
    
    mutating func statusesUpdatedPages(pagination: Pagination?) -> (RequestRange?, RequestRange?) {
        return self.statusesPaginatableData.updatedPages(pagination: pagination,
                                                         nextPage: self.statusesNextPage,
                                                         previousPage: self.statusesPreviousPage)
    }
    
    mutating func pollFollowers(client: Client, account: Account, range: RequestRange? = nil) {
        self.followersPaginatableData.pollData(client: client, range: range, existingData: self.followers, filters: []) { (
            followers: [Account],
            pagination: Pagination?
        ) in
            GlobalStore.dispatch(SetFollowers(value: followers, account: account))
            GlobalStore.dispatch(SetFollowersPage(value: pagination, account: account))
        }
    }
    
    func followersProvider(range: RequestRange?) -> Request<[Account]> {
        guard let account = self.account else { fatalError("Cannot request statuses for nil account") }
        guard let range = range else { return Accounts.followers(id: account.id, range: .limit(80)) }
        return Accounts.followers(id: account.id, range: range)
    }
    
    mutating func followersUpdatedPages(pagination: Pagination?) -> (RequestRange?, RequestRange?) {
        return self.followersPaginatableData.updatedPages(pagination: pagination,
                                                          nextPage: self.followersNextPage,
                                                          previousPage: self.followersPreviousPage)
    }
    
    mutating func pollFollowing(client: Client, account: Account, range: RequestRange? = nil) {
        self.followingPaginatableData.pollData(client: client, range: range, existingData: self.following, filters: []) { (
            following: [Account],
            pagination: Pagination?
        ) in
            GlobalStore.dispatch(SetFollowing(value: following, account: account))
            GlobalStore.dispatch(SetFollowingPage(value: pagination, account: account))
        }
    }
    
    func followingProvider(range: RequestRange?) -> Request<[Account]> {
        guard let account = self.account else { fatalError("Cannot request statuses for nil account") }
        guard let range = range else { return Accounts.following(id: account.id, range: .limit(80)) }
        return Accounts.following(id: account.id, range: range)
    }
    
    mutating func followingUpdatedPages(pagination: Pagination?) -> (RequestRange?, RequestRange?) {
        return self.followingPaginatableData.updatedPages(pagination: pagination,
                                                          nextPage: self.followingNextPage,
                                                          previousPage: self.followingPreviousPage)
    }
}

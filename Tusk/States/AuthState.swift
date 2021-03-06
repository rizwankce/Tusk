//
//  AuthState.swift
//  Tusk
//
//  Created by Patrick Perini on 8/11/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import Foundation
import MastodonKit
import ReSwift
import KeychainAccess

struct AuthState: StateType {
    struct LoadAuth: Action { let value: String? }
    struct CreateAppForInstance: Action { let value: String }
    struct SetInstance: Action { let value: String? }
    struct SetClientInfo: Action {
        let id: String
        let secret: String
    }
    struct SetAccessToken: Action { let value: String? }
    struct PollAccessToken: Action { let code: String }
    struct ClearAuth: Action {}
    
    static let defaultInstance: String = "mastodon.social"
    static let redirectURL: String = "tusk://oauth"
    static let keychain = Keychain(service: Bundle.main.bundleIdentifier!).synchronizable(true)
    
    var instance: String? = nil
    var clientID: String? = nil
    var clientSecret: String? = nil
    
    var code: String?
    var oauthURL: URL?
    
    var accessToken: String?
    var storedAccountID: String?
    var client: Client?
    
    var baseURL: String? {
        guard let instance = self.instance else { return nil }
        return "https://\(instance)"
    }
    
    static func reducer(action: Action, state: AuthState?) -> AuthState {
        let oldInstance = state?.instance
        var state = state ?? AuthState()
        
        switch action {
        case let action as LoadAuth: state.loadAuth(account: action.value)
        case let action as CreateAppForInstance: state.createAppForInstance(instance: action.value)
        case let action as SetInstance: state.instance = action.value
        case let action as SetClientInfo: state.setClientInfo(id: action.id, secret: action.secret)
        case let action as SetAccessToken: state.setAccessToken(token: action.value)
        case let action as PollAccessToken: do {
            state.code = action.code
            state.pollAccessToken(client: state.client, code: action.code)
            }
        case is ClearAuth: do {
            state = AuthState()
            AuthState.clearAll()
            }
        case let action as ErrorsState.AddError: state.handleError(error: action.value)
        default: break
        }
        
        if (oldInstance != state.instance) {
            if let url = state.baseURL {
                state.client = Client(baseURL: url)
            } else {
                state.client = nil
            }
        }
        
        if (state.client?.accessToken != state.accessToken) {
            state.client?.accessToken = state.accessToken
        }
        
        return state
    }
    
    private mutating func loadAuth(account: String? = nil) {
        guard let account = account ?? self.accountsInKeychain.first else { return }
        (self.accessToken, self.instance) = self.authForAccount(account: account)
    }
    
    private mutating func createAppForInstance(instance: String) {
        self.instance = instance // temporarily
        guard let baseURL = self.baseURL else { return }
        
        let client = Client(baseURL: baseURL)
        let request =  Clients.register(
            clientName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String,
            redirectURI: AuthState.redirectURL,
            scopes: [.read, .write, .follow],
            website: "https://pcperini.com"
        )
        
        client.run(request: request, success: { (resp, _) in
            GlobalStore.dispatch(SetInstance(value: instance))
            GlobalStore.dispatch(SetClientInfo(id: resp.clientID, secret: resp.clientSecret))
        }, failure: { (_) in
            GlobalStore.dispatch(ClearAuth())
        })
    }
    
    private mutating func setClientInfo(id: String, secret: String) {
        self.clientID = id
        self.clientSecret = secret
        do {
            self.oauthURL = try Login.oauthURL(baseURL: self.baseURL!,
                                               clientID: id,
                                               scopes: [.follow, .read, .write],
                                               redirectURI: AuthState.redirectURL)?.asURL()
        } catch {
            Log.error("error Login.oauthURL(\(self.baseURL!), \(id)) 🚨 Error: \(error)\n")
            GlobalStore.dispatch(ErrorsState.AddError(value: error))
            GlobalStore.dispatch(ClearAuth())
            
            self.clientID = nil
            self.clientSecret = nil
        }
    }
    
    private mutating func setAccessToken(token: String?) {
        self.accessToken = token
        
        guard let token = token, let instance = self.instance else { return }
        self.saveAccessToken(token: token, forInstance: instance)
    }
    
    func pollAccessToken(client: Client?, code: String) {
        guard let client = client, let id = self.clientID, let secret = self.clientSecret else { return }
        let request = Login.oauth(clientID: id,
                                  clientSecret: secret,
                                  code: code,
                                  redirectURI: AuthState.redirectURL)
        
        client.run(request: request, success: { (resp, _) in
            GlobalStore.dispatch(SetAccessToken(value: resp.accessToken))
            GlobalStore.dispatch(AppState.PollData())
        }, failure: { (_) in
            GlobalStore.dispatch(ClearAuth())
            GlobalStore.dispatch(SetAccessToken(value: nil))
        })
    }
    
    func handleError(error: Error) {
        if let error = error as? ClientError {
            switch error {
            case .mastodonError(let description): DispatchQueue.main.async {
                if (description.lowercased().contains("access token")) {
                    GlobalStore.dispatch(ClearAuth())
                }
                }
            default: break
            }
        }
    }
}

extension AuthState {
    var accountsInKeychain: [String] {
        get { return (AuthState.keychain["access_tokens"] ?? "").split(separator: ",").map { (s) in String(s) } }
        set { AuthState.keychain["access_tokens"] = newValue.joined(separator: ",") }
    }
    
    func authForAccount(account: String) -> (String?, String?) {
        return (AuthState.keychain["\(account).token"], AuthState.keychain["\(account).instance"])
    }
    
    mutating func saveAccessToken(token: String, forInstance instance: String) {
        let id = UUID().uuidString
        self.storedAccountID = id
        
        self.accountsInKeychain += [id]
        AuthState.keychain["\(id).token"] = token
        AuthState.keychain["\(id).instance"] = instance
    }
    
    static func clearAll() {
        do {
            try AuthState.keychain.removeAll()
        } catch {
            Log.error("error AuthState.keychain.removeAll() 🚨 Error: \(error)\n")
            GlobalStore.dispatch(ErrorsState.AddError(value: error))
        }
    }
}

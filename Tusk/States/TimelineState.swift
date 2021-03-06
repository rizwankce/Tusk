//
//  TimelineState.swift
//  Tusk
//
//  Created by Patrick Perini on 8/11/18.
//  Copyright © 2018 Patrick Perini. All rights reserved.
//

import Foundation
import MastodonKit
import ReSwift

struct TimelineState: StatusesState {    
    var statuses: [Status] = []
    var baseFilters: [(Status) -> Bool] = [{ $0.visibility != .direct }]
    
    var nextPage: RequestRange? = nil
    var previousPage: RequestRange? = nil
    lazy var paginatingData: PaginatingData<Status, Status> = PaginatingData<Status, Status>(provider: self.provider)
    
    func provider(range: RequestRange? = nil) -> Request<[Status]> {
        guard let range = range else { return Timelines.home(range: .limit(40)) }
        return Timelines.home(range: range)
    }
}

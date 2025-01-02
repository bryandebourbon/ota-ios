//
//  HomescreenWidgetLiveActivity.swift
//  HomescreenWidget
//
//  Created by Bryan de Bourbon on 1/1/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct HomescreenWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct HomescreenWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HomescreenWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension HomescreenWidgetAttributes {
    fileprivate static var preview: HomescreenWidgetAttributes {
        HomescreenWidgetAttributes(name: "World")
    }
}

extension HomescreenWidgetAttributes.ContentState {
    fileprivate static var smiley: HomescreenWidgetAttributes.ContentState {
        HomescreenWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: HomescreenWidgetAttributes.ContentState {
         HomescreenWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: HomescreenWidgetAttributes.preview) {
   HomescreenWidgetLiveActivity()
} contentStates: {
    HomescreenWidgetAttributes.ContentState.smiley
    HomescreenWidgetAttributes.ContentState.starEyes
}

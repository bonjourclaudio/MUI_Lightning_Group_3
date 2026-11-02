//
//  ChargeBadgeView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// The + / − sign on a charged cloud – the same symbols and colours as in the storm bar.
struct ChargeBadgeView: View {
    @Environment(AppModel.self) private var appModel
    let slot: Int

    var body: some View {
        if slot < appModel.slotCharges.count, let charge = appModel.slotCharges[slot] {
            Image(systemName: charge == .positive ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(charge == .positive ? Color.red : Color.blue)
                .shadow(color: .black.opacity(0.25), radius: 4)
        }
    }
}

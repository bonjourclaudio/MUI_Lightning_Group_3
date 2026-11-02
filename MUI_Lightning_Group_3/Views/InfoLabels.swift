//
//  InfoLabels.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Small glass labels that sit directly on the objects they explain, connected with a
/// thin leader line (positions: `SceneController.anchor(for:)` / `offset(for:)`).
enum InfoLabel: String, CaseIterable, Identifiable {
    case sun, land, thermals, slope
    case condensation, updraft, freezing, anvil
    case droplets, iceCrystals, graupel, rain

    var id: String { "label-\(rawValue)" }

    var title: String {
        switch self {
        case .sun: return "Sun"
        case .land: return "Land heats quickly"
        case .thermals: return "Warm air rises"
        case .slope: return "Forced upwards"
        case .condensation: return "Condensation"
        case .updraft: return "Updraft"
        case .freezing: return "0 °C – freezing level"
        case .anvil: return "Anvil"
        case .droplets: return "Supercooled droplets"
        case .iceCrystals: return "Ice crystals  +"
        case .graupel: return "Graupel & hail  −"
        case .rain: return "Rain & hail"
        }
    }

    var detail: String {
        switch self {
        case .sun: return "Heats the ground – not the air directly"
        case .land: return "Bare rock and soil warm up fast in the sun"
        case .thermals: return "Warm air is lighter than the air around it"
        case .slope: return "Wind pushes moist air up the mountain"
        case .condensation: return "Rising air cools, water vapour turns into droplets"
        case .updraft: return "Warm air keeps feeding the cloud from below"
        case .freezing: return "Above this level water freezes – ice and graupel form"
        case .anvil: return "Stopped by the tropopause at about 10–12 km"
        case .droplets: return "Still liquid below 0 °C, they freeze onto ice"
        case .iceCrystals: return "Light, carried to the top – positively charged"
        case .graupel: return "Heavy, gathers in the middle – negatively charged"
        case .rain: return "Too heavy for the updraft – melts on the way down"
        }
    }

    var symbol: String {
        switch self {
        case .sun: return "sun.max.fill"
        case .land: return "thermometer.sun.fill"
        case .thermals: return "arrow.up.circle.fill"
        case .slope: return "wind"
        case .condensation: return "cloud.fill"
        case .updraft: return "arrow.up"
        case .freezing: return "snowflake"
        case .anvil: return "arrow.left.and.right"
        case .droplets: return "drop.fill"
        case .iceCrystals: return "plus.circle.fill"
        case .graupel: return "minus.circle.fill"
        case .rain: return "cloud.heavyrain.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sun, .land, .thermals: return .orange
        case .droplets: return .cyan
        case .iceCrystals: return .red
        case .graupel: return .blue
        case .freezing: return .mint
        default: return .white
        }
    }
}

struct InfoLabelView: View {
    let label: InfoLabel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: label.symbol)
                .font(.title3)
                .foregroundStyle(label.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(label.title)
                    .font(.headline)
                Text(label.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 340, alignment: .leading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 22))
    }
}

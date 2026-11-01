//
//  InAppMapSheet.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//


//
//  InAppMapSheet.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//


import SwiftUI
import MapKit

struct InAppMapSheet: View {
    let location: String

    @State private var position: MapCameraPosition = .automatic
    @State private var searchResult: MKMapItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if let searchResult {
                    Marker(searchResult.name ?? location,
                           coordinate: searchResult.placemark.coordinate)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(location)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let searchResult {
                    Button {
                        searchResult.openInMaps()
                    } label: {
                        Text("Open in Apple Maps")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.black.opacity(0.75))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.75))
                            .clipShape(Circle())
                    }
                }
                Spacer()
            }

            .padding(.top, 14)

            .padding(.horizontal, 14)
        }
        .task {
            await loadLocation()
        }
    }

    private func loadLocation() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location

        do {
            let response = try await MKLocalSearch(request: request).start()

            if let first = response.mapItems.first {
                searchResult = first

                let coordinate = first.placemark.coordinate

                position = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.03,
                            longitudeDelta: 0.03
                        )
                    )
                )
            }
        } catch {
            print(error)
        }
    }
}

//
//  ProfileMusicTabSupport.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct ProfileMusicSongCard: View {
    let song: ProfileMusicSong

    var body: some View {
        TrackDetailLink(reference: TrackDetailReference(song)) {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(song.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let artistName = song.displayArtistName {
                    Text(artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = song.resolvedArtworkURL(size: 260) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct ProfileFollowingArtistCard: View {
    let artist: ProfileFollowingArtist

    var body: some View {
        Group {
            if artist.source == "apple_music", let sourceId = artist.sourceId, !sourceId.isEmpty {
                NavigationLink {
                    AppleArtistDetailView(sourceId: sourceId, ownerUsername: nil)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .frame(width: 92, height: 92)
                .clipShape(Circle())

            Text(artist.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 108, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = artist.resolvedImageURL(size: 180) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct ProfilePrivateSectionHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Image(systemName: "eye.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct ProfileDiscographyFilterChips: View {
    @Binding var selectedFilter: ProfileDiscographyFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProfileDiscographyFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedFilter == filter
                                    ? Theme.accentColor.opacity(0.85)
                                    : .white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ProfileDiscographyLatestReleaseCard: View {
    let item: ProfileDiscographyItem
    var canManage: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            NavigationLink {
                ProfileDiscographyDestinationView(item: item)
            } label: {
                cardContent
            }
            .buttonStyle(.plain)

            if canManage, item.isReleaseCollection || item.type == "single" {
                NavigationLink {
                    manageDestination
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardContent: some View {
        HStack(spacing: 16) {
            artwork
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Release")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .textCase(.uppercase)

                Text(item.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(item.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var manageDestination: some View {
        if item.type == "single" {
            EditPublishedTrackView(trackId: item.id)
        } else if item.isReleaseCollection {
            EditPublishedReleaseView(
                releaseId: item.id,
                initialName: item.title,
                initialArtworkURL: item.imageUrl
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = item.resolvedImageURL(size: 264) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct ProfileDiscographyRow: View {
    let item: ProfileDiscographyItem
    var canManage: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProfileDiscographyDestinationView(item: item)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)

            if canManage, item.isReleaseCollection || item.type == "single" {
                NavigationLink {
                    manageDestination
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            artwork
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var manageDestination: some View {
        if item.type == "single" {
            EditPublishedTrackView(trackId: item.id)
        } else if item.isReleaseCollection {
            EditPublishedReleaseView(
                releaseId: item.id,
                initialName: item.title,
                initialArtworkURL: item.imageUrl
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = item.resolvedImageURL(size: 144) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct ProfileDiscographyDestinationView: View {
    let item: ProfileDiscographyItem

    var body: some View {
        Group {
            if item.isReleaseCollection {
                NicheAlbumDetailView(albumId: item.id)
            } else {
                NicheTrackDetailView(trackId: item.id)
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

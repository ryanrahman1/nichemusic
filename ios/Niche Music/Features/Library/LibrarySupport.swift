//
//  LibrarySupport.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

extension ProfileMusicSong {
    func resolvedArtworkURL(size: Int = 260) -> URL? {
        resolvedAppleArtworkURL(artworkUrl, size: size)
    }

    var displayArtistName: String? {
        guard let artistName else { return nil }
        let trimmed = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ProfileFollowingArtist {
    func resolvedImageURL(size: Int = 180) -> URL? {
        resolvedAppleArtworkURL(imageUrl, size: size)
    }
}

struct LibrarySectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct LibraryQuickAccessRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

struct LibraryFilterChips: View {
    @Binding var selectedFilter: LibraryContentFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryContentFilter.allCases) { filter in
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
            .padding(.horizontal, 16)
        }
    }
}

struct LibrarySearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct LibrarySongCard: View {
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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let artistName = song.displayArtistName {
                    Text(artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
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

struct LibraryHorizontalRail<Content: View>: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var emptyMessage: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibrarySectionHeader(title: title, actionTitle: actionTitle, action: action)

            if let emptyMessage {
                Text(emptyMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        content()
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct LibraryTrendingSongCard: View {
    let track: CatalogTrack

    var body: some View {
        NavigationLink {
            trackDetailDestination(TrackDetailReference(
                id: track.source == "apple_music" ? nil : track.id,
                source: track.source,
                sourceId: track.sourceId
            ))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(track.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let artistName = track.artistName, !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(track.artworkUrl, size: 260) {
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

struct LibraryTrendingAlbumCard: View {
    let album: CatalogAlbum

    var body: some View {
        NavigationLink {
            if album.source == "apple_music" {
                AppleAlbumDetailView(sourceId: album.sourceId)
            } else {
                NicheAlbumDetailView(albumId: album.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(album.artworkUrl, size: 260) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
        }
    }
}

struct LibraryTrendingArtistCard: View {
    let artist: CatalogArtist

    var body: some View {
        Group {
            if artist.source == "apple_music", !artist.sourceId.isEmpty {
                NavigationLink {
                    AppleArtistDetailView(sourceId: artist.sourceId, ownerUsername: nil)
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
        VStack(spacing: 8) {
            artwork
                .frame(width: 92, height: 92)
                .clipShape(Circle())

            Text(artist.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 108)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(artist.imageUrl, size: 180) {
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

struct LibraryCatalogItemRow: View {
    let item: AnyCatalogItem

    var body: some View {
        switch item {
        case .song(let track):
            CatalogTrackRow(track: track, showsArtist: true)
        case .album(let album):
            CatalogAlbumRow(album: album)
        case .artist(let artist):
            LibraryArtistListRow(artist: artist)
        case .profileSong(let song):
            TrackDetailLink(reference: TrackDetailReference(song)) {
                librarySongRow(
                    title: song.name,
                    subtitle: song.displayArtistName ?? "",
                    artworkUrl: song.artworkUrl
                )
            }
        case .followingArtist(let artist):
            LibraryFollowingArtistRow(artist: artist)
        case .searchSong(let song):
            NavigationLink {
                AppleMusicDetailView(sourceId: song.id)
            } label: {
                librarySongRow(
                    title: song.attributes.name,
                    subtitle: song.attributes.artistName,
                    artworkUrl: song.artworkURL?.absoluteString
                )
            }
            .buttonStyle(.plain)
        case .searchAlbum(let album):
            NavigationLink {
                AppleAlbumDetailView(sourceId: album.id)
            } label: {
                librarySongRow(
                    title: album.attributes.name,
                    subtitle: album.artistName,
                    artworkUrl: album.artworkURL?.absoluteString
                )
            }
            .buttonStyle(.plain)
        case .searchArtist(let artist):
            NavigationLink {
                AppleArtistDetailView(sourceId: artist.id, ownerUsername: nil)
            } label: {
                librarySongRow(
                    title: artist.attributes.name,
                    subtitle: "Artist",
                    artworkUrl: artist.artworkURL?.absoluteString
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func librarySongRow(title: String, subtitle: String, artworkUrl: String?) -> some View {
        HStack(spacing: 12) {
            if let url = resolvedAppleArtworkURL(artworkUrl, size: 120) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 52, height: 52)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct LibraryArtistListRow: View {
    let artist: CatalogArtist

    var body: some View {
        Group {
            if artist.source == "apple_music", !artist.sourceId.isEmpty {
                NavigationLink {
                    AppleArtistDetailView(sourceId: artist.sourceId, ownerUsername: nil)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if let url = resolvedAppleArtworkURL(artist.imageUrl, size: 120) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 52, height: 52)
            }

            Text(artist.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct LibraryFollowingArtistRow: View {
    let artist: ProfileFollowingArtist

    var body: some View {
        NavigationLink {
            if artist.source == "apple_music", let sourceId = artist.sourceId, !sourceId.isEmpty {
                AppleArtistDetailView(sourceId: sourceId, ownerUsername: nil)
            }
        } label: {
            HStack(spacing: 12) {
                if let url = artist.resolvedImageURL(size: 120) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 52, height: 52)
                }

                Text(artist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

func filterSongs(_ songs: [ProfileMusicSong], source: LibrarySource) -> [ProfileMusicSong] {
    songs.filter { source.matches($0.source) }
}

func filterTracks(_ tracks: [CatalogTrack], source: LibrarySource) -> [CatalogTrack] {
    tracks.filter { source.matches($0.source) }
}

func filterAlbums(_ albums: [CatalogAlbum], source: LibrarySource) -> [CatalogAlbum] {
    albums.filter { source.matches($0.source) }
}

func filterArtists(_ artists: [CatalogArtist], source: LibrarySource) -> [CatalogArtist] {
    artists.filter { source.matches($0.source) }
}

func filterFollowingArtists(_ artists: [ProfileFollowingArtist], source: LibrarySource) -> [ProfileFollowingArtist] {
    artists.filter { source.matches($0.source) }
}

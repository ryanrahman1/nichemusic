//
//  APIEndpoint.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

struct APIEndpoint {
    let path: String
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
}

enum Endpoints {
    static let session = APIEndpoint(path: "/session")
    static let loginEmail = APIEndpoint(path: "/login/email")
    static let signupEmail = APIEndpoint(path: "/signup/email")
    static let signupUsernameAvailable = APIEndpoint(path: "/signup/username/available")
    static let emailVerifySend = APIEndpoint(path: "/email/verify/send")
    static let emailVerifyConfirm = APIEndpoint(path: "/email/verify/confirm")
    static let passwordResetSend = APIEndpoint(path: "/password/reset/send")
    static let logout = APIEndpoint(path: "/logout")
    static let feedHome = APIEndpoint(path: "/feed/home")
    static let feedImpression = APIEndpoint(path: "/feed/impression")
    static let feedView = APIEndpoint(path: "/feed/view")
    static let feedSkip = APIEndpoint(path: "/feed/skip")
    static let feedOpenProfile = APIEndpoint(path: "/feed/open-profile")
    static let inbox = APIEndpoint(path: "/inbox")
    static let messagesCreate = APIEndpoint(path: "/messages/create")
    static let messagesRead = APIEndpoint(path: "/messages/read")
    static let messagesDmEnsure = APIEndpoint(path: "/messages/dm/ensure")

    static func conversation(id: String) -> APIEndpoint {
        APIEndpoint(path: "/conversations/\(id.urlEncoded)")
    }
    static let me = APIEndpoint(path: "/me")
    static let myFollowers = APIEndpoint(path: "/me/followers")
    static let myFollowing = APIEndpoint(path: "/me/following")
    static let myPosts = APIEndpoint(path: "/me/posts")
    static let myReposts = APIEndpoint(path: "/me/reposts")
    static let myDiscography = APIEndpoint(path: "/me/discography")
    static let musicMeLiked = APIEndpoint(path: "/music/me/liked")
    static let musicMeSaved = APIEndpoint(path: "/music/me/saved")
    static let musicMeFollowing = APIEndpoint(path: "/music/me/following")

    static func musicUserLiked(username: String) -> APIEndpoint {
        APIEndpoint(path: "/music/users/\(username.urlEncoded)/liked")
    }

    static func musicUserFollowing(username: String) -> APIEndpoint {
        APIEndpoint(path: "/music/users/\(username.urlEncoded)/following")
    }

    static func userPlaylists(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/playlists")
    }
    static let musicLibrarySongs = APIEndpoint(path: "/music/library/songs")
    static let musicLibraryAlbums = APIEndpoint(path: "/music/library/albums")
    static let musicLibraryArtists = APIEndpoint(path: "/music/library/artists")
    static let myPlaylists = APIEndpoint(path: "/me/playlists")
    static let myPlaylistTrackMembership = APIEndpoint(path: "/me/playlists/track-membership")
    static let createPlaylist = APIEndpoint(path: "/playlists/create")
    static let musicMatchesCheck = APIEndpoint(path: "/music-matches/check")
    static let musicMatchesLatest = APIEndpoint(path: "/music-matches/latest")
    static let dailyTriviaToday = APIEndpoint(path: "/games/trivia/today")
    static let myFriends = APIEndpoint(path: "/me/friends")
    static let myNotifications = APIEndpoint(path: "/me/notifications")

    static func musicMatchRespond(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music-matches/\(id.urlEncoded)/respond")
    }

    static func dailyTriviaAnswer(questionId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/trivia/\(questionId.urlEncoded)/answer")
    }

    static let auxCreateRoom = APIEndpoint(path: "/games/aux/rooms/create")
    static let auxJoinRoom = APIEndpoint(path: "/games/aux/rooms/join")

    static func auxRoom(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)")
    }

    static func auxLeaveRoom(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/leave")
    }

    static func auxUpdateSettings(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/settings")
    }

    static func auxStartSubmissions(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/start-submissions")
    }

    static func auxSubmitSong(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/submit-song")
    }

    static func auxCreateBracket(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/bracket/create")
    }

    static func auxStartBracket(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/bracket/start")
    }

    static func auxStartMatchupA(roomId: String, matchupId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/matchups/\(matchupId.urlEncoded)/start-a")
    }

    static func auxStartMatchupB(roomId: String, matchupId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/matchups/\(matchupId.urlEncoded)/start-b")
    }

    static func auxStartVoting(roomId: String, matchupId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/matchups/\(matchupId.urlEncoded)/start-voting")
    }

    static func auxVote(roomId: String, matchupId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/matchups/\(matchupId.urlEncoded)/vote")
    }

    static func auxRevealMatchup(roomId: String, matchupId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/matchups/\(matchupId.urlEncoded)/reveal")
    }

    static func auxPlayAgain(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/play-again")
    }

    static func auxCreateRematch(roomId: String) -> APIEndpoint {
        APIEndpoint(path: "/games/aux/rooms/\(roomId.urlEncoded)/rematch/create")
    }

    static func markNotificationRead(id: String) -> APIEndpoint {
        APIEndpoint(path: "/me/notifications/\(id.urlEncoded)/read")
    }

    static let markAllNotificationsRead = APIEndpoint(path: "/me/notifications/all/read")
    static let registerPushDevice = APIEndpoint(path: "/me/notifications/device")
    static let deletePushDevice = APIEndpoint(path: "/me/notifications/device/delete")

    static func publicShareTrack(id: String) -> APIEndpoint {
        APIEndpoint(path: "/public/share/track/\(id.urlEncoded)")
    }

    static func publicShareArtist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/public/share/artist/\(id.urlEncoded)")
    }

    static func likePost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/like")
    }
    static func repostPost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/repost")
    }
    static func unlikePost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/unlike")
    }
    static func unrepostPost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/unrepost")
    }
    
    static func trackLyrics(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/lyrics")
    }
    
    static func getTrackComments(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/comments")
    }

    static func createNicheTrackComment(trackId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(trackId.urlEncoded)/comments/create")
    }

    static func nicheTrackCommentReplies(trackId: String, commentId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(trackId.urlEncoded)/comments/\(commentId.urlEncoded)/replies")
    }

    static func likeNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/like")
    }

    static func unlikeNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/unlike")
    }

    static func pinNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/pin")
    }

    static func unpinNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/unpin")
    }

    static func hideNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/hide")
    }

    static func unhideNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/unhide")
    }

    static func getPostComments(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/comments")
    }

    static func createPostComment(postId: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(postId.urlEncoded)/comments/create")
    }

    static func postCommentReplies(postId: String, commentId: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(postId.urlEncoded)/comments/\(commentId.urlEncoded)/replies")
    }

    static func likeComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/like")
    }

    static func unlikeComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/unlike")
    }

    static func pinComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/pin")
    }

    static func unpinComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/unpin")
    }

    static func hideComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/hide")
    }

    static func unhideComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/unhide")
    }

    static func deleteComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/comments/\(id.urlEncoded)/delete")
    }

    static func deleteNicheComment(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/comments/\(id.urlEncoded)/delete")
    }

    static let appleMusicSearch = APIEndpoint(path: "/music/apple/search")
    static let nicheTrackSearch = APIEndpoint(path: "/music/niche/search")
    static let globalSearchSuggestions = APIEndpoint(path: "/search/suggestions")
    static let globalSearch = APIEndpoint(path: "/search")
    static let discoverHome = APIEndpoint(path: "/discover")

    static func badge(id: String) -> APIEndpoint {
        APIEndpoint(path: "/badges/\(id.urlEncoded)")
    }

    static func badgeHolders(badgeId: String) -> APIEndpoint {
        APIEndpoint(path: "/badges/\(badgeId.urlEncoded)/holders")
    }

    static func appleMusicSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/apple/songs/\(id.urlEncoded)")
    }

    static func appleMusicAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/apple/albums/\(id.urlEncoded)")
    }

    static func appleMusicAlbumSync(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/apple/albums/\(id.urlEncoded)/sync-tracks")
    }

    static func appleMusicArtist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/apple/artists/\(id.urlEncoded)")
    }

    static func appleMusicArtistDiscography(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/apple/artists/\(id.urlEncoded)/load-discography")
    }

    static func nicheAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(id.urlEncoded)")
    }

    static func nicheRelease(id: String) -> APIEndpoint {
        nicheAlbum(id: id)
    }

    static func likeSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/songs/\(id.urlEncoded)/like")
    }

    static func unlikeSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/songs/\(id.urlEncoded)/unlike")
    }

    static func likeNicheSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/like")
    }

    static func unlikeNicheSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/unlike")
    }

    static func saveNicheSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/save")
    }

    static func unsaveNicheSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)/unsave")
    }

    static func saveSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/songs/\(id.urlEncoded)/save")
    }

    static func unsaveSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/songs/\(id.urlEncoded)/unsave")
    }

    static func shareSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/songs/\(id.urlEncoded)/share")
    }

    static func likeAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/albums/\(id.urlEncoded)/like")
    }

    static func unlikeAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/albums/\(id.urlEncoded)/unlike")
    }

    static func saveAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/albums/\(id.urlEncoded)/save")
    }

    static func unsaveAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/albums/\(id.urlEncoded)/unsave")
    }

    static func shareAlbum(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/albums/\(id.urlEncoded)/share")
    }

    static func followArtist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/artists/\(id.urlEncoded)/follow")
    }

    static func unfollowArtist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/artists/\(id.urlEncoded)/unfollow")
    }

    static func shareArtist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/artists/\(id.urlEncoded)/share")
    }

    static func playlist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(id.urlEncoded)")
    }

    static func addPlaylistItem(playlistId: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(playlistId.urlEncoded)/items/add")
    }

    static func deletePlaylistItem(playlistId: String, itemId: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(playlistId.urlEncoded)/items/\(itemId.urlEncoded)/delete")
    }

    static func movePlaylistItem(playlistId: String, itemId: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(playlistId.urlEncoded)/items/\(itemId.urlEncoded)/move")
    }

    static func updatePlaylistImage(playlistId: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(playlistId.urlEncoded)/image")
    }

    static func updatePlaylist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(id.urlEncoded)/update")
    }

    static func deletePlaylist(id: String) -> APIEndpoint {
        APIEndpoint(path: "/playlists/\(id.urlEncoded)/delete")
    }

    static func custom(path: String) -> APIEndpoint {
        APIEndpoint(path: path)
    }
    static let updateProfile = APIEndpoint(path: "/me/update")
    static let meAvatar = APIEndpoint(path: "/auth/me/avatar")

    static func user(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)")
    }

    static func userFollowers(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/followers")
    }

    static func userFollowing(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/following")
    }

    static func userDiscography(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/discography")
    }

    static func userPosts(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/posts")
    }

    static func userReposts(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/reposts")
    }

    static func followUser(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/follow")
    }

    static func unfollowUser(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/unfollow")
    }

    static let myFollowRequests = APIEndpoint(path: "/me/follow_requests")
    static let myBlocks = APIEndpoint(path: "/me/blocks")

    static func acceptFollowRequest(userId: String) -> APIEndpoint {
        APIEndpoint(path: "/me/follows/\(userId.urlEncoded)/accept")
    }

    static func rejectFollowRequest(userId: String) -> APIEndpoint {
        APIEndpoint(path: "/me/follows/\(userId.urlEncoded)/reject")
    }

    static func blockUser(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/block")
    }

    static func unblockUser(username: String) -> APIEndpoint {
        APIEndpoint(path: "/users/\(username.urlEncoded)/unblock")
    }

    static func post(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)")
    }

    static let presignPostMedia = APIEndpoint(path: "/posts/media/presign")
    static let createPost = APIEndpoint(path: "/posts/create")

    static func updatePost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/update")
    }

    static func deletePost(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/delete")
    }

    static func postLikes(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/likes")
    }

    static func postReposts(id: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.urlEncoded)/reposts")
    }

    static let deleteAccount = APIEndpoint(path: "/me/delete")
    static let createReport = APIEndpoint(path: "/reports/create")

    static let createNicheTrackDraft = APIEndpoint(path: "/music/niche/songs/draft/create")

    static let listNicheTrackDrafts = APIEndpoint(path: "/music/niche/songs/drafts")

    static func nicheTrackDraft(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/draft/\(id.urlEncoded)")
    }

    static func deleteNicheTrackDraft(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/draft/\(id.urlEncoded)/delete")
    }

    static func reuploadNicheTrackDraftMusic(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/draft/\(id.urlEncoded)/music/upload")
    }

    static func updateNicheTrackDraft(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/draft/\(id.urlEncoded)/update")
    }

    static func publishNicheTrackDraft(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/draft/\(id.urlEncoded)/publish")
    }

    static let createNicheReleaseDraft = APIEndpoint(path: "/music/niche/releases/draft/create")

    static let listNicheReleaseDrafts = APIEndpoint(path: "/music/niche/releases/drafts")

    static func nicheReleaseDraft(releaseDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/draft/\(releaseDraftId.urlEncoded)")
    }

    static func deleteNicheReleaseDraft(releaseDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/draft/\(releaseDraftId.urlEncoded)/delete")
    }

    static func deleteNicheReleaseTrackDraft(releaseDraftId: String, trackDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseDraftId.urlEncoded)/tracks/draft/\(trackDraftId.urlEncoded)/delete")
    }

    static func reuploadNicheReleaseTrackDraftMusic(releaseDraftId: String, trackDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseDraftId.urlEncoded)/tracks/draft/\(trackDraftId.urlEncoded)/music/upload")
    }

    static func updateNicheReleaseDraft(releaseDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/draft/\(releaseDraftId.urlEncoded)/update")
    }

    static func createNicheReleaseTrackDraft(releaseDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseDraftId.urlEncoded)/tracks/draft/create")
    }

    static func updateNicheReleaseTrackDraft(releaseDraftId: String, trackDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseDraftId.urlEncoded)/tracks/draft/\(trackDraftId.urlEncoded)/update")
    }

    static func publishNicheReleaseDraft(releaseDraftId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseDraftId.urlEncoded)/publish")
    }

    static func updatePublishedNicheTrack(trackId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/tracks/\(trackId.urlEncoded)/update")
    }

    static func deletePublishedNicheTrack(trackId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/tracks/\(trackId.urlEncoded)/delete")
    }

    static func updatePublishedNicheRelease(releaseId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseId.urlEncoded)/update")
    }

    static func deletePublishedNicheRelease(releaseId: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/releases/\(releaseId.urlEncoded)/delete")
    }

    static func nicheSong(id: String) -> APIEndpoint {
        APIEndpoint(path: "/music/niche/songs/\(id.urlEncoded)")
    }

}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}

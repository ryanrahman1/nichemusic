export type HelpId =
  | "title"
  | "slug"
  | "template"
  | "type"
  | "subtitle"
  | "excerpt"
  | "tags"
  | "cover"
  | "coverAlt"
  | "coverCredit"
  | "imageUrl"
  | "body"
  | "imageSize"
  | "imageCaption"
  | "imageCredit"
  | "imageAlt"
  | "artworkUrl"
  | "artist"
  | "album"
  | "releaseDate"
  | "rating"
  | "verdict"
  | "label"
  | "scene"
  | "badge"
  | "portraitUrl"
  | "interviewee"
  | "role"
  | "location"
  | "interviewDate"
  | "spotlightArtist"
  | "spotlightScene"
  | "widgets";

export const FIELD_HELP: Record<HelpId, { label: string; body: string }> = {
  title: {
    label: "Title",
    body: "The main headline people will see. For reviews, the artist and album can live in the review fields below, so this can be a shorter headline if you want.",
  },

  slug: {
    label: "Slug",
    body: "The part of the URL after /news/. Use lowercase letters, numbers, and hyphens. Try not to change it after publishing or old links can break.",
  },

  template: {
    label: "Template",
    body: "Changes how the article header looks. Standard is a normal story, while reviews, interviews, and spotlights get their own layouts. The body editor stays the same.",
  },

  type: {
    label: "Type",
    body: "The kind of story this is: news, review, feature, interview, or spotlight. This is separate from the template, which only changes the layout.",
  },

  subtitle: {
    label: "Subtitle",
    body: "A short line or two under the headline that gives the reader a little more context. Leave it blank if the title already says enough.",
  },

  excerpt: {
    label: "Excerpt",
    body: "A short summary used in article cards, search, and previews. Keep it to a sentence or two.",
  },

  tags: {
    label: "Tags",
    body: "Add topics, scenes, genres, or artists separated by commas. Example: hyperpop, seoul, underground.",
  },

  cover: {
    label: "Cover image",
    body: "The main image for the article. Upload one or paste an image URL. It’ll also be used in places like article cards and homepage features.",
  },

  imageUrl: {
    label: "Image URL",
    body: "Paste a direct image link if you’d rather not upload one. Make sure the image can actually load from the original site.",
  },

  coverAlt: {
    label: "Cover alt",
    body: "A short description of what’s in the cover image for accessibility.",
  },

  coverCredit: {
    label: "Cover credit",
    body: "Who took, made, or supplied the cover image.",
  },

  body: {
    label: "Article body",
    body: "Write the actual story here. You can use headings, links, quotes, lists, and images. Niche handles the page layout and styling for you.",
  },

  imageSize: {
    label: "Image size",
    body: "Normal stays inside the article column. Wide stretches out a bit more, and full goes edge to edge. Use the bigger sizes when the image actually needs the space.",
  },

  imageCaption: {
    label: "Caption",
    body: "Optional text shown under the image. Use it to explain what the reader is looking at.",
  },

  imageCredit: {
    label: "Image credit",
    body: "The photographer, artist, publication, or source for the image.",
  },

  imageAlt: {
    label: "Alt text",
    body: "A short description of the image for people using screen readers.",
  },

  artworkUrl: {
    label: "Album artwork",
    body: "Square cover art used in the album review header. Upload it or paste an image URL.",
  },

  artist: {
    label: "Artist",
    body: "The artist or group being reviewed. This gets the big treatment in the review header.",
  },

  album: {
    label: "Album",
    body: "The album or project title.",
  },

  releaseDate: {
    label: "Release date",
    body: "When the album came out. Write it how you want it to appear, like Aug 22, 2026.",
  },

  rating: {
    label: "Rating",
    body: "Score out of 10. Just enter the number, like 8.4 — the page handles the rest.",
  },

  verdict: {
    label: "Verdict",
    body: "The main takeaway from the review in one or two sentences. Think of it as the review’s thesis.",
  },

  label: {
    label: "Label",
    body: "The label that released the project. If it was self-released, that works too.",
  },

  scene: {
    label: "Scene",
    body: "A short description of where the music fits, whether that’s a sound, scene, or place. Example: Seoul hyperpop.",
  },

  badge: {
    label: "Badge",
    body: "Optional label for something notable, like Album of the Month or Best New Music. Leave it blank if there isn’t one.",
  },

  portraitUrl: {
    label: "Portrait",
    body: "A photo of the person or artist. Interviews and spotlights use this prominently in the header.",
  },

  interviewee: {
    label: "Interviewee",
    body: "The person you interviewed.",
  },

  role: {
    label: "Role / description",
    body: "A short description under their name, like producer, vocalist, founder, or creative director.",
  },

  location: {
    label: "Location",
    body: "Where they’re based or where the interview happened. Keep it short.",
  },

  interviewDate: {
    label: "Interview date",
    body: "When the interview happened. This is separate from the article’s publish date.",
  },

  spotlightArtist: {
    label: "Artist",
    body: "The artist this spotlight is about. Their name becomes the main headline in the spotlight header.",
  },

  spotlightScene: {
    label: "Scene",
    body: "Optional context for the spotlight, like a city, genre, or scene.",
  },

  widgets: {
    label: "Side widgets",
    body: "Optional extras for artist spotlights. Add essential tracks, related artists, a YouTube video, or another Niche article. You don’t need to use every widget.",
  },
};
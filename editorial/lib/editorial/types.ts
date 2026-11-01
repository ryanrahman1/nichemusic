export const ARTICLE_TYPES = [
  "review",
  "news",
  "feature",
  "interview",
  "spotlight",
] as const;

export type ArticleType = (typeof ARTICLE_TYPES)[number];

export const ARTICLE_TEMPLATES = [
  "standard",
  "album_review",
  "interview",
  "artist_spotlight",
] as const;

export type ArticleTemplate = (typeof ARTICLE_TEMPLATES)[number];

export const ARTICLE_STATUSES = [
  "draft",
  "submitted",
  "in_review",
  "changes_requested",
  "approved",
  "published",
  "rejected",
  "archived",
] as const;

export type ArticleStatus = (typeof ARTICLE_STATUSES)[number];

export type ImageSize = "normal" | "wide" | "full";

export type RichTextDoc = {
  type: "doc";
  content?: unknown[];
};

export type AlbumReviewData = {
  album: string;
  artist: string;
  releaseDate: string;
  rating: string;
  verdict: string;
  artworkUrl: string;
  label: string;
  scene: string;
  badge: string;
};

export type InterviewData = {
  interviewee: string;
  role: string;
  portraitUrl: string;
  location: string;
  interviewDate: string;
};

export type SpotlightEntity = {
  id: string;
  title: string;
  subtitle?: string;
  cover?: string | null;
  href?: string | null;
  blurb?: string;
};

export type SpotlightWidget =
  | {
      id: string;
      type: "essential_tracks";
      items: SpotlightEntity[];
    }
  | {
      id: string;
      type: "if_you_like";
      artistName: string;
      items: SpotlightEntity[];
    }
  | {
      id: string;
      type: "watch";
      youtubeUrl: string;
      caption: string;
    }
  | {
      id: string;
      type: "featured_on_niche";
      editorialId: string;
      slug: string;
    };

export type SpotlightData = {
  artist: string;
  portraitUrl: string;
  location: string;
  scene: string;
  widgets: SpotlightWidget[];
};

export type TemplateData = AlbumReviewData & InterviewData & SpotlightData;

export type TemplateTextKey = {
  [K in keyof TemplateData]: TemplateData[K] extends string ? K : never;
}[keyof TemplateData];

export type CmsPayload = {
  type: "cms";
  template: ArticleTemplate;
  templateData: TemplateData;
  doc: RichTextDoc;
};

export type EditorialContent = {
  version: 1;
  blocks: unknown[];
};

export type WriterWorkspace = {
  writer: WriterProfile | null;
  permissions: WriterPermissions;
  articles: ArticleCard[];
  queue: ArticleCard[];
  catalog: ArticleCard[];
};

export type OnboardingProfile = {
  username: string | null;
  displayName: string | null;
  bio: string | null;
  location: string | null;
};

export type WriterPermissions = {
  canWrite: boolean;
  canSubmit: boolean;
  canReview: boolean;
  canPublish: boolean;
  canManageWriters: boolean;
  canEditAny: boolean;
  canDelete: boolean;
};

export type WriterAccount = {
  id: string;
  username: string;
  displayName: string | null;
  avatarUrl: string | null;
  followersCount?: number;
};

export type WriterStats = {
  publishedCount: number;
  editedCount: number;
  followersCount: number;
  totalViews?: number;
  qualifiedReads?: number;
};

export type EngagementStats = {
  pageViews: number;
  uniqueReaders: number;
  qualifiedReads: number;
  totalEngagedSeconds: number;
};

export type AnalyticsArticle = {
  id: string;
  title: string;
  slug: string;
  type?: string;
  status: string;
  publishedAt: string | null;
  stats: EngagementStats;
};

export type WriterAnalytics = {
  days: number;
  totals: EngagementStats;
  articles: AnalyticsArticle[];
};

export type DeskAnalytics = {
  days: number;
  totals: EngagementStats;
  popular: AnalyticsArticle[];
};

export type WriterProfile = {
  id: string;
  slug: string;
  role: string;
  bio: string | null;
  displayName: string | null;
  specialties: string[];
  location: string | null;
  onboardingCompleted: boolean;
  joinedAt?: string;
  stats?: WriterStats;
  profile: WriterAccount | null;
};

export type PublicWriter = {
  id: string;
  slug: string;
  role: string;
  bio: string | null;
  displayName: string | null;
  specialties: string[];
  location: string | null;
  joinedAt: string;
  stats: WriterStats;
  profile: WriterAccount | null;
};

export type ArticleTag = {
  id: string;
  name: string;
  slug: string;
};

export type ArticleCredit = {
  creditType: string;
  position: number;
  writer: {
    id: string;
    slug: string;
    profile: {
      id: string;
      username: string;
      displayName: string | null;
      avatarUrl: string | null;
    } | null;
    role?: string | null;
    bio?: string | null;
  } | null;
};

export type HomeNewMusicTrack = {
  id: string;
  source: "apple_music";
  sourceId: string;
  name: string | null;
  artworkUrl: string | null;
  previewUrl: string | null;
  releaseDate: string | null;
  artist: { id: string; name: string | null } | null;
};

export type HomeNewMusicPick = {
  track: HomeNewMusicTrack;
  review: { slug: string; title: string; type: string } | null;
};

export type AdminNewMusicPick = {
  id: string;
  position: number;
  showFrom: string | null;
  showUntil: string | null;
  live: boolean;
  track: HomeNewMusicTrack | null;
  review: {
    id: string;
    slug: string;
    title: string;
    type: string;
    status: string;
  } | null;
};

export type EditorialHome = {
  hero: ArticleCard | null;
  premiumPromo: ArticleCard | null;
  featured: ArticleCard[];
  newMusic: HomeNewMusicPick[];
  promo: ArticleCard | null;
  latest: ArticleCard[];
  error?: string;
};

export type ArticleCard = {
  id: string;
  slug: string;
  title: string;
  subtitle: string | null;
  excerpt: string | null;
  type: ArticleType;
  template?: ArticleTemplate;
  templateData?: Partial<TemplateData> | Record<string, unknown>;
  status?: ArticleStatus;
  coverImageUrl: string | null;
  coverImageAlt: string | null;
  coverImageCredit?: string | null;
  isSponsored: boolean;
  sponsorName: string | null;
  publishedAt: string | null;
  createdAt: string;
  updatedAt?: string;
  tags: ArticleTag[];
  credits?: ArticleCredit[];
  content?: EditorialContent | unknown;
  metaTitle?: string | null;
  metaDescription?: string | null;
};

export type EditorialSearch = {
  query: string;
  articles: ArticleCard[];
  writers: PublicWriter[];
  tags: ArticleTag[];
  error?: string;
};

export type PresignedUpload = {
  uploadUrl: string;
  objectKey: string;
  publicUrl: string;
  contentType: string;
  maxBytes: number;
};

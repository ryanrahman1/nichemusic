BASE:
{
  "version": 1,
  "kind": "text",
  "caption": "string",
  "media": [],
  "track": null,
  "original_sound": null,
  "template": null,
  "metadata": {},
  "analytics": {}
}

{
    "version": 1,
    "kind": "text",
    "caption": "..."
}

{
    "version": 1,
    "kind": "image",
    "caption": "...",
    "media": [...
    ]
}

{
  "version": 1,
  "kind": "video",
  "caption": "...",
  "media": [...],
  "original_sound": {...}
}

{
  "version": 1,
  "kind": "track",
  "caption": "...",
  "track": {...}
}

{
  "version": 1,
  "kind": "pmo",
  "caption": "...",
  "track": {...},
  "template": {
    "name": "pmo",
    "data": {...}
  }
}

{
  "version": 1,
  "kind": "poll",
  "caption": "...",
  "template": {
    "name": "poll",
    "data": {
      "question": "best late night artist?",
      "options": [
        {"id": "a", "label": "Frank Ocean"},
        {"id": "b", "label": "SZA"}
      ],
      "multiple": false
    }
  }
}

EXAMPLE PMO: 
{
  "version": 1,
  "kind": "pmo",
  "caption": "put me on to songs like this",

  "media": [
    {
      "kind": "image",
      "url": "...",
      "width": 1080,
      "height": 1080,
      "duration_ms": null
    }
  ],

  "track": {
    "id": "trk_123",
    "source": "apple_music",
    "title": "Nights",
    "artist_name": "Frank Ocean",
    "artwork_url": "...",
    "preview_url": "..."
  },

  "original_sound": null,

  "template": {
    "name": "pmo",
    "data": {
      "prompt": "put me on to songs like this",
      "allow_track_replies": true
    }
  },

  "metadata": {
    "layout": "pmo_card",
    "source": "ios_composer_v1"
  },

  "analytics": {
    "has_media": true,
    "has_track": true,
    "has_original_sound": false,
    "media_count": 1
  }
}
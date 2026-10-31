ARG LMS_VERSION=9.1.2
FROM lmscommunity/lyrionmusicserver:${LMS_VERSION}

# Transcoding helpers that LMS and its plugins (Qobuz, Tidal, ...) call out to
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg flac sox faad mpg123 \
 && rm -rf /var/lib/apt/lists/*

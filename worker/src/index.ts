/**
 * Clicky Proxy Worker
 *
 * Proxies requests to Claude, OpenRouter, and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat             → Anthropic Messages API (streaming)
 *   POST /tts              → ElevenLabs TTS API
 *   POST /tts-openai       → OpenAI TTS API (gpt-4o-mini-tts)
 *   POST /transcribe-token → AssemblyAI token
 *   POST /transcribe-audio → OpenAI Whisper (Live Companion system-audio WAV)
 *
 * Note: OpenRouter mode runs client-side (the app calls openrouter.ai directly
 * with a user-supplied, Keychain-stored key), so the Worker holds no OpenRouter
 * secret and exposes no OpenRouter route.
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  OPENAI_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      console.log(`[${url.pathname}] ${request.method}`);
      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/tts-openai") {
        return await handleOpenAITTS(request, env);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }

      if (url.pathname === "/transcribe-audio") {
        return await handleTranscribeAudio(request, env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeAudio(request: Request, env: Env): Promise<Response> {
  // Forward the app's multipart WAV upload to OpenAI Whisper with the server-held
  // key, so the key never ships in the app and system audio stays within the proxy.
  const MAX_AUDIO_BYTES = 25 * 1024 * 1024; // OpenAI per-file limit; also caps cost abuse
  const contentLength = request.headers.get("content-length");
  if (contentLength && parseInt(contentLength, 10) > MAX_AUDIO_BYTES) {
    console.error(`[/transcribe-audio] rejected oversize body ${contentLength}B (max ${MAX_AUDIO_BYTES})`);
    return new Response(
      JSON.stringify({ error: "Audio file too large (max 25MB)" }),
      { status: 413, headers: { "content-type": "application/json" } }
    );
  }

  const contentType = request.headers.get("content-type") || "multipart/form-data";
  const body = await request.arrayBuffer();

  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), 30000);
  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
        "content-type": contentType,
      },
      body,
      signal: abortController.signal,
    });
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-audio] OpenAI error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  // ElevenLabs takes the voice in the URL path, not the JSON body. The app may send
  // a per-request `voiceId` so the user's selected voice reaches ElevenLabs; if it's
  // absent we fall back to the Worker's configured ELEVENLABS_VOICE_ID (preserving
  // the original single-voice behavior). The `voiceId` field is stripped from the
  // forwarded body since ElevenLabs doesn't expect it there.
  const parsedBody = await request.json().catch(() => ({} as Record<string, unknown>));
  const { voiceId: requestedVoiceId, ...elevenLabsBody } = parsedBody as {
    voiceId?: string;
    [key: string]: unknown;
  };
  const voiceId =
    typeof requestedVoiceId === "string" && requestedVoiceId.trim().length > 0
      ? requestedVoiceId.trim()
      : env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: JSON.stringify(elevenLabsBody),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

async function handleOpenAITTS(request: Request, env: Env): Promise<Response> {
  // Synthesize speech with OpenAI's TTS model using the server-held key, so the key
  // never ships in the app. The app posts { text, voice } where voice is one of the
  // OpenAI voices (alloy, ash, ballad, coral, echo, sage, shimmer, verse). Returns
  // MP3 audio, matching the /tts route so the app can play it back the same way.
  // Fail clearly if the OpenAI key isn't configured as a Worker secret, instead of
  // sending `Bearer undefined` upstream and surfacing a confusing OpenAI 401.
  if (!env.OPENAI_API_KEY) {
    return new Response(
      JSON.stringify({ error: "OpenAI TTS is not configured (missing OPENAI_API_KEY secret on the Worker)." }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }

  const parsedBody = await request.json().catch(() => ({} as Record<string, unknown>));
  const { text, voice } = parsedBody as { text?: string; voice?: string };

  const trimmedText = typeof text === "string" ? text.trim() : "";
  if (trimmedText.length === 0) {
    return new Response(
      JSON.stringify({ error: "Missing text for OpenAI TTS" }),
      { status: 400, headers: { "content-type": "application/json" } }
    );
  }

  // Cap input length so a caller can't run up an unbounded per-character OpenAI bill
  // on this public route (mirrors the size cap on /transcribe-audio). A spoken reply
  // is short; 4000 chars is generous.
  const MAX_TTS_CHARS = 4000;
  if (trimmedText.length > MAX_TTS_CHARS) {
    return new Response(
      JSON.stringify({ error: `Text too long for OpenAI TTS (max ${MAX_TTS_CHARS} characters).` }),
      { status: 413, headers: { "content-type": "application/json" } }
    );
  }

  const selectedVoice =
    typeof voice === "string" && voice.trim().length > 0 ? voice.trim() : "alloy";

  // Bound the upstream call so a slow/hung OpenAI response can't hold the request
  // open indefinitely (mirrors the AbortController timeout on /transcribe-audio).
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), 30000);

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini-tts",
        input: trimmedText,
        voice: selectedVoice,
        response_format: "mp3",
      }),
      signal: abortController.signal,
    });
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "AbortError";
    return new Response(
      JSON.stringify({ error: timedOut ? "OpenAI TTS timed out." : "OpenAI TTS request failed." }),
      { status: timedOut ? 504 : 502, headers: { "content-type": "application/json" } }
    );
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts-openai] OpenAI TTS error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

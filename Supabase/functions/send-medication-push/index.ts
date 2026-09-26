import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1"

const iosTopic = Deno.env.get("APNS_IOS_TOPIC") ?? "com.carecompanion.txst"
const watchTopic = Deno.env.get("APNS_WATCH_TOPIC") ?? "com.carecompanion.txst.watchkitapp"
const sandbox = Deno.env.get("APNS_SANDBOX") !== "false"

type Dose = { id: string; name: string; dosage: string; profile_id: string; account_id?: string }
type DeviceToken = { token: string; platform: string }
type PushBody = {
  reason?: string
  medication_id?: string
  account_id?: string
  kind?: string
  detail?: string
  senior_id?: string
  message_id?: string
  activity_id?: string
  audio_path?: string
  sender_name?: string
  sender_id?: string
}
type Alert = {
  title: string
  body: string
  collapseID?: string
  category?: string
  extra?: Record<string, string>
  timeSensitive?: boolean
}

let cachedJwt: { value: string; expires: number } | null = null

Deno.serve(async (req) => {
  if (!apnsConfigured()) {
    return json({ configured: false, sent: 0 })
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  const admin = createClient(supabaseUrl, serviceKey)
  const body = await req.json().catch(() => ({})) as PushBody
  const auth = req.headers.get("Authorization") ?? ""

  if (body.reason === "family") {
    return await notifyFamily(admin, anonKey, supabaseUrl, auth, body)
  }

  if (body.reason === "senior") {
    return await notifySenior(admin, anonKey, supabaseUrl, auth, body)
  }

  if (body.reason === "mood") {
    return await notifyMoodPrompt(admin, anonKey, supabaseUrl, auth, body)
  }

  if (body.reason === "now") {
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: auth } },
    })
    const { data: userData, error } = await userClient.auth.getUser()
    if (error || !userData.user || !body.medication_id) {
      return json({ error: "unauthorized" }, 401)
    }
    const dose = await loadMedication(admin, body.medication_id)
    if (!dose) return json({ error: "not found" }, 404)
    const allowed = await isAccountMember(admin, dose.account_id, userData.user.id)
    if (!allowed || !dose.profile_id) return json({ error: "unauthorized" }, 403)
    const sent = await pushDose(admin, dose)
    return json({ configured: true, sent })
  }

  if (auth !== `Bearer ${serviceKey}`) {
    return json({ error: "unauthorized" }, 401)
  }
  const { data: due, error } = await admin.rpc("claim_due_medications")
  if (error) return json({ error: error.message }, 500)
  let sent = 0
  for (const row of (due ?? []) as Dose[]) {
    sent += await pushDose(admin, row)
  }
  return json({ configured: true, sent })
})

function apnsConfigured(): boolean {
  return Boolean(Deno.env.get("APNS_PRIVATE_KEY") && Deno.env.get("APNS_KEY_ID") && Deno.env.get("APNS_TEAM_ID"))
}

async function loadMedication(admin: ReturnType<typeof createClient>, id: string) {
  const { data } = await admin.from("medications")
    .select("id, name, dosage, account_id, senior_id")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle()
  if (!data) return null
  const { data: senior } = await admin.from("account_seniors")
    .select("profile_id")
    .eq("id", data.senior_id)
    .maybeSingle()
  return {
    id: data.id as string,
    name: data.name as string,
    dosage: (data.dosage as string) ?? "",
    account_id: data.account_id as string,
    profile_id: (senior?.profile_id as string | null) ?? null,
  }
}

async function isAccountMember(admin: ReturnType<typeof createClient>, accountId: string, profileId: string) {
  const { data } = await admin.from("account_members")
    .select("id")
    .eq("account_id", accountId)
    .eq("profile_id", profileId)
    .maybeSingle()
  return Boolean(data)
}

async function notifyFamily(
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  supabaseUrl: string,
  auth: string,
  body: PushBody,
): Promise<Response> {
  const kind = body.kind ?? ""
  const accountId = body.account_id ?? ""
  if (!accountId || !["mood", "message", "medication", "sos"].includes(kind)) {
    return json({ error: "invalid" }, 400)
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  })
  const { data: userData, error } = await userClient.auth.getUser()
  if (error || !userData.user) return json({ error: "unauthorized" }, 401)

  const { data: membership } = await admin.from("account_members")
    .select("id")
    .eq("account_id", accountId)
    .eq("profile_id", userData.user.id)
    .eq("role", "senior")
    .maybeSingle()
  if (!membership) return json({ error: "unauthorized" }, 403)
  if (kind === "sos") {
    const seniorId = body.senior_id ?? ""
    const { data: owned } = await admin.from("account_seniors")
      .select("id")
      .eq("id", seniorId)
      .eq("account_id", accountId)
      .eq("profile_id", userData.user.id)
      .is("deleted_at", null)
      .maybeSingle()
    if (!owned) return json({ error: "unauthorized" }, 403)
  }

  const { data: senior } = await admin.from("account_seniors")
    .select("name")
    .eq("account_id", accountId)
    .eq("profile_id", userData.user.id)
    .is("deleted_at", null)
    .maybeSingle()
  const { data: profile } = await admin.from("profiles")
    .select("display_name")
    .eq("id", userData.user.id)
    .maybeSingle()
  const name = String(senior?.name || profile?.display_name || "Your senior").trim() || "Your senior"
  const detail = String(body.detail ?? "").replace(/\s+/g, " ").trim().slice(0, 140)
  const copy = familyCopy(kind, name, detail)
  if (!copy) return json({ error: "invalid" }, 400)
  const messageID = body.message_id ?? ""
  const activityID = body.activity_id ?? ""

  const { data: family } = await admin.from("account_members")
    .select("profile_id")
    .eq("account_id", accountId)
    .eq("role", "family")
  const profileIDs = ((family ?? []) as { profile_id: string }[]).map((row) => row.profile_id).filter(Boolean)
  if (profileIDs.length === 0) return json({ configured: true, sent: 0 })

  const { data } = await admin.from("device_tokens")
    .select("token, platform")
    .in("profile_id", profileIDs)
  const tokens = (data ?? []) as DeviceToken[]
  const jwt = await appleJwt()
  let sent = 0
  for (const device of tokens) {
    const topic = device.platform === "watch" ? watchTopic : iosTopic
    const ok = await sendAlert(device.token, topic, jwt, {
      title: copy.title,
      body: copy.body,
      collapseID: kind === "mood"
        ? `family-mood-${activityID || "latest"}`
        : kind === "medication"
        ? `family-medication-${activityID || "latest"}`
        : kind === "sos"
        ? `family-sos-${body.senior_id}`
        : kind === "message"
        ? `family-message-${messageID || "new"}`
        : undefined,
      category: kind === "sos" ? "carecompanion.sos" : kind === "message" ? "carecompanion.message" : undefined,
      extra: kind === "sos"
        ? { kind: "sos", seniorID: body.senior_id ?? "" }
        : kind === "message"
        ? { kind: "message", audience: "family", messageID, senderName: name, body: copy.body }
        : kind === "mood" || kind === "medication"
        ? { kind, audience: "family", activityID, body: copy.body }
        : undefined,
      timeSensitive: kind === "sos",
    })
    if (ok === "drop") {
      await admin.from("device_tokens").delete().eq("token", device.token)
    } else if (ok === "sent") {
      sent += 1
    }
  }
  return json({ configured: true, sent })
}

async function notifyMoodPrompt(
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  supabaseUrl: string,
  auth: string,
  body: PushBody,
): Promise<Response> {
  const accountId = body.account_id ?? ""
  const seniorId = body.senior_id ?? ""
  if (!accountId || !seniorId) return json({ error: "invalid" }, 400)
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  })
  const { data: userData, error } = await userClient.auth.getUser()
  if (error || !userData.user) return json({ error: "unauthorized" }, 401)
  const allowed = await isAccountMember(admin, accountId, userData.user.id)
  if (!allowed) return json({ error: "unauthorized" }, 403)
  const { data: senior } = await admin.from("account_seniors")
    .select("profile_id")
    .eq("id", seniorId)
    .eq("account_id", accountId)
    .is("deleted_at", null)
    .maybeSingle()
  const profileId = (senior?.profile_id as string | null) ?? null
  if (!profileId) return json({ configured: true, sent: 0 })
  const { data } = await admin.from("device_tokens")
    .select("token, platform")
    .eq("profile_id", profileId)
  const tokens = (data ?? []) as DeviceToken[]
  const jwt = await appleJwt()
  let sent = 0
  for (const device of tokens) {
    const topic = device.platform === "watch" ? watchTopic : iosTopic
    const ok = await sendAlert(device.token, topic, jwt, {
      title: "How are you?",
      body: "Tell your family. This stays until you choose.",
      collapseID: "mood-prompt",
      category: "carecompanion.mood",
      extra: { kind: "moodPrompt" },
      timeSensitive: true,
    })
    if (ok === "drop") {
      await admin.from("device_tokens").delete().eq("token", device.token)
    } else if (ok === "sent") {
      sent += 1
    }
  }
  return json({ configured: true, sent })
}

async function notifySenior(
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  supabaseUrl: string,
  auth: string,
  body: PushBody,
): Promise<Response> {
  const accountId = body.account_id ?? ""
  const detail = String(body.detail ?? "").replace(/\s+/g, " ").trim().slice(0, 140)
  if (!accountId || !detail) return json({ error: "invalid" }, 400)
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  })
  const { data: userData, error } = await userClient.auth.getUser()
  if (error || !userData.user) return json({ error: "unauthorized" }, 401)
  const { data: membership } = await admin.from("account_members")
    .select("id")
    .eq("account_id", accountId)
    .eq("profile_id", userData.user.id)
    .eq("role", "family")
    .maybeSingle()
  if (!membership) return json({ error: "unauthorized" }, 403)

  const { data: seniors } = await admin.from("account_members")
    .select("profile_id")
    .eq("account_id", accountId)
    .eq("role", "senior")
  const profileIDs = ((seniors ?? []) as { profile_id: string }[]).map((row) => row.profile_id).filter(Boolean)
  if (profileIDs.length === 0) return json({ configured: true, sent: 0 })

  const senderName = String(body.sender_name ?? "").trim() || "Family"
  const { data } = await admin.from("device_tokens")
    .select("token, platform")
    .in("profile_id", profileIDs)
  const tokens = (data ?? []) as DeviceToken[]
  const jwt = await appleJwt()
  let sent = 0
  for (const device of tokens) {
    const topic = device.platform === "watch" ? watchTopic : iosTopic
    const ok = await sendAlert(device.token, topic, jwt, {
      title: senderName,
      body: detail,
      collapseID: `message-${body.sender_id || userData.user.id}`,
      category: "carecompanion.message",
      extra: {
        kind: "message",
        messageID: body.message_id ?? "",
        senderID: body.sender_id ?? userData.user.id,
        senderName,
        body: detail,
        audioPath: body.audio_path ?? "",
      },
    })
    if (ok === "drop") {
      await admin.from("device_tokens").delete().eq("token", device.token)
    } else if (ok === "sent") {
      sent += 1
    }
  }
  return json({ configured: true, sent })
}

function familyCopy(kind: string, name: string, detail: string): { title: string; body: string } | null {
  switch (kind) {
    case "mood":
      return { title: `${name} updated their mood`, body: detail || "Open CareCompanion to see how they're feeling." }
    case "message":
      return { title: `${name} sent a message`, body: detail || "New message" }
    case "medication":
      return { title: `${name} took their medicine`, body: detail || "Marked as taken" }
    case "sos":
      return { title: `${name} needs help`, body: "SOS. Open CareCompanion to FaceTime them." }
    default:
      return null
  }
}

async function pushDose(admin: ReturnType<typeof createClient>, dose: Dose): Promise<number> {
  if (!dose.profile_id) return 0
  const { data } = await admin.from("device_tokens")
    .select("token, platform")
    .eq("profile_id", dose.profile_id)
  const tokens = (data ?? []) as DeviceToken[]
  const jwt = await appleJwt()
  let sent = 0
  for (const device of tokens) {
    const topic = device.platform === "watch" ? watchTopic : iosTopic
    const ok = await sendAlert(device.token, topic, jwt, {
      title: dose.name,
      body: dose.dosage || "Time to take this.",
      collapseID: `medication-${dose.id}`,
      category: "carecompanion.medication",
      extra: { medicationID: dose.id, dosage: dose.dosage },
      timeSensitive: true,
    })
    if (ok === "drop") {
      await admin.from("device_tokens").delete().eq("token", device.token)
    } else if (ok === "sent") {
      sent += 1
    }
  }
  return sent
}

async function sendAlert(token: string, topic: string, jwt: string, alert: Alert): Promise<"sent" | "drop" | "fail"> {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com"
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    "apns-topic": topic,
    "apns-push-type": "alert",
    "apns-priority": "10",
  }
  if (alert.collapseID) headers["apns-collapse-id"] = alert.collapseID
  const aps: Record<string, unknown> = {
    alert: { title: alert.title, body: alert.body },
    sound: "default",
  }
  if (alert.category) aps.category = alert.category
  if (alert.timeSensitive) aps["interruption-level"] = "time-sensitive"
  const response = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers,
    body: JSON.stringify({ aps, ...(alert.extra ?? {}) }),
  })
  if (response.status === 200) return "sent"
  if (response.status === 410 || response.status === 400) return "drop"
  return "fail"
}

async function appleJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJwt && cachedJwt.expires > now + 60) return cachedJwt.value
  const keyId = Deno.env.get("APNS_KEY_ID") ?? ""
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? ""
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(Deno.env.get("APNS_PRIVATE_KEY") ?? ""),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }))
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }))
  const signingInput = new TextEncoder().encode(`${header}.${claims}`)
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, signingInput)
  const value = `${header}.${claims}.${base64url(new Uint8Array(signature))}`
  cachedJwt = { value, expires: now + 50 * 60 }
  return value
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s/g, "")
  const binary = atob(body)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return bytes.buffer
}

function base64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

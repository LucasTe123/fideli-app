import { createClient } from "@supabase/supabase-js";
import { PassType, PKPass } from "npm:passkit-generator@3.6.0";
import { Buffer } from "node:buffer";
import webpush from "npm:web-push@3.6.7";
// @ts-types="npm:@types/qrcode@1.5.5"
import QRCode from "npm:qrcode@1.5.4";
import type { IMagickImage } from "npm:@imagemagick/magick-wasm@^0.0.35";
import {
  phosphorStampPngActive,
  phosphorStampPngInactive,
} from "./phosphor_icons.ts";
import {
  illustratedStampPngActive,
  illustratedStampPngInactive,
} from "./stamp_illustrations.ts";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

type MagickModule = typeof import("npm:@imagemagick/magick-wasm@^0.0.35");
let Drawables: MagickModule["Drawables"];
let CompositeOperator: MagickModule["CompositeOperator"];
let Gravity: MagickModule["Gravity"];
let ImageMagick: MagickModule["ImageMagick"];
let MagickColor: MagickModule["MagickColor"];
let MagickColors: MagickModule["MagickColors"];
let MagickFormat: MagickModule["MagickFormat"];
let MagickGeometry: MagickModule["MagickGeometry"];
let Point: MagickModule["Point"];

let imageMagickReady: Promise<void> | null = null;

function ensureImageMagick() {
  imageMagickReady ??= (async () => {
    const magick = await import("npm:@imagemagick/magick-wasm@^0.0.35");
    Drawables = magick.Drawables;
    CompositeOperator = magick.CompositeOperator;
    Gravity = magick.Gravity;
    ImageMagick = magick.ImageMagick;
    MagickColor = magick.MagickColor;
    MagickColors = magick.MagickColors;
    MagickFormat = magick.MagickFormat;
    MagickGeometry = magick.MagickGeometry;
    Point = magick.Point;
    const magickWasm = await Deno.readFile(
      new URL(
        "magick.wasm",
        import.meta.resolve("npm:@imagemagick/magick-wasm@^0.0.35"),
      ),
    );
    await magick.initializeImageMagick(magickWasm);
  })();
  return imageMagickReady;
}

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-fideli-device-token",
};

const icon = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAB0AAAAdCAIAAADZ8fBYAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAHaADAAQAAAABAAAAHQAAAADeexZRAAACdklEQVRIDdWVz2sTQRTH58fumlpImmJtWhtsYxUsUvAm4kFQMAcLHjx78iDqQfRQEK8echF78x/wIHhoTypCQZEqLcQiUpUoCdiD1sS2SWPrbnbGtzu6ncxusxsxB4cc3uzM+8w3331vFnPOUQcG6QDTQf5vXK0tH/KrbK5sU4wQ/DgyGdrfjc8OahpMm0cb3IXv7M4Hq9ZAxKUANN2FJ/YFQOEIHLEeBPQnQ45Y5ChN78Y3D+uDXT6prvBI702BWmFQIIdzFSgoHWqp1JUbxvVDW/99AQ3R+9fQVlwFGsVTT+yOXAUa0VOZq9YvXELzFTZVsAJLqmqhwgbzKguuLI2gIwkiiq8Vd9Xk9z5Z9QYy3EqR6xSWcu+spSqn7hLjTtNdOqCNJ2Tg71its6SBL2a0GEWQJnu6BtD31lKN76IIuhbSdIyuHtSyAxR7+iV+cL/NlZ2W3RvDt8acjlrZ4tcXzbLJ4xoGoxyl2FF6up9KqKZQ9VcsHt9DDKIDF6DftviVvAlvMqmjWDcYikOhAAnW6x29/INfe23CNSaciVF8qEe7nCEn+1QDvRQRhCyX6uztOtPdXYSSumUXnr/MsJpC8U9DuCf66N2jBtSGjQlijfLso8Vn+Ync0+LXqp8lPwnxQWx9/MW+sbDxeeZ+bbmCelJwS44P905Pnhnpj8ssOQ7RK7ZmU/T20HpjzUbxlPOpMOibUuVc7klxZUdDIukV9IevihemZjc3zT8fDHt0uHdmMjuWTspKRRxcZ/598OT8sRGNnHrw4iMSDYeRZdrT86XRgYQB7dw82tDbnLg9g07xd5x6zvb2yJEfCqn/gBsooFPcX87xE0NblR+hAAAAAElFTkSuQmCC", "base64");
const icon2x = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAADoAAAA6CAIAAABu2d1/AAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAOqADAAQAAAABAAAAOgAAAACjq6v0AAAE4UlEQVRoBe2ZzW/cRBjGZ2Lv5kOARFsaSFqy4UJRqcQf0CJBLgjUcijiAAeSVlrYnqEnbuXEpSkRbRKUSpwQB+DApUGQoqaoWwnRForUJq0QraKkKB9QlZTdtcc849m1vF6P7fF4D5HWh2R2PJ75+fHjd953lzqOQ7bO0bV1UDlpB7edz6ujbkddT4EtZgbTA29H45cNdnWDGXJNEPQR9l8bMHZ20yQAbcQtr9njC9YDiwAklIURYjtkrGBsy4eeD+GnbdrVLq+x8YVahRFDQgJWxsjYsHlo0AjhknS1Rd2yy1qVs8IAsMHYsKHEilvIHvfSqn1q0YpidYhNXNYB5dXlb4HkcUR3x7O6fh0tmIfUWTNWt7zKPonWFazqfvULpPw4/Bf72/zdWqzFeCCVX/2rZIOLmHVqIdKviAPcr2pxwA8q2hngKvhVJWa1sqJH91Urx8YB4deC8bo2K3C11OUeiH63vJg1qLWQp3T6WYRfI/YtbASIrzxmZaGrIE6Je2mVxegq8gHtd8vTVTTSeNdljYxZ9fiqvMcG4Fo/Kqub9N3i+YDy5K18gR61GS/HvluuB0az9oAHrYALXcej44DwayF7Dyjj8pwwmlXELM6qIIHHkbCRaOpE+xb22JaYheLnCoofSYYORPGF16tPGf098kG+W4nHvbhqTyxatchcOzTPQmA+edP61w6vfAQrc5Oe7ckKNVwSj1uxCVhl9w55XNagX92Cwqo5pFdS2iDjcQsK8+CAZIRPVK8ZjzvSz6c7c8uCEl3N1GBF52hLzIovftwCGMWPEmsidTEolLiha3CPRbCDB6CrzLJ1XZ9R01UIHK+uGBcgFqyurk2PcnYFrLVHclTK6tQTX1VdBYZa4T53zz59y0LigoPXsc31Fljfv1pFQfF0H8VXB1AxcIik58hwGl3FVEnVFaNf7jeg69Rt6+0h1IZNun63Yn/gskLXpYcYRbZ1UzjbO9DExyOpPOBNoqauuOzPTWeor+mlAyt0/Y8Rs9GN/wO99PE8FcCCFcVPOg9o4XoXiwY8AF1bE1+PGK6ArvqsWE7NDAFQaDa7bB+/FsKKkTjLXUHpjl7jrV1UU1exdJp814Nefuh8eL26aUtjFlj/+Kc6dH8pE1asq4X7ZA89vieX6+LPOuSgFH5Y++nHiclvz87dCBmg3qWFi03uzd3miefz4AoSu6wrc+f+vnF7k+ZLU/Mz32dArIUr1Hljt/HRvlwTMcW0dPncN+u//U66e7B3Vx1y7LP5mR90iTPABfThXSaIITbXmLM6K1/PbPxcpvlunsjwPpd4ev6sHnE2uIL4xD64gjJm3/vy043yefrYdpLro4bp+qJOXNIjTrNNCA+E/v1qiRU//mL92q9kxxDN1aX1j3SYg2/2Txf3Hx15zt+fsK0Vd1vXODxI7x98ofRXpWLbwgaBMdwVzClNX4RBjo7sCZyN/ZixumK9z8/ffHfyQsVxaFe42aBxjpIzxQOqxOHTxd5l9IB3Xnp26r0XYWRghY6ExkiIj00rx4q2qOtpXJy8UK3gl6pG4hNgx81QMlE8UHplrxEoVAIjGx8z9m5jWv4fGvfmzdkrdwz574CMOdfvrN9de1B44lH/tbJ2G9WVLanT3xbv6gBFX9vBjdZH72xHXT39oq/uqButj97Z/wE2QkZ6/moWrAAAAABJRU5ErkJggg==", "base64");

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });
const passTypeId = Deno.env.get("APPLE_PASS_TYPE_ID")!;
const teamId = Deno.env.get("APPLE_TEAM_ID")!;
const functionBaseUrl = `${supabaseUrl}/functions/v1/wallet`;
const publicClubUrl = "https://fideli.site";
const publicCronKey =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcnNzbmhsYndrdWZuaGdxZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4OTAyMzAsImV4cCI6MjA5NjQ2NjIzMH0.Y-P94zJJKx4n5L5f-23CoKFaQ3gP1ssvcKv6cn3uP1U";
function publicClubForBusiness(businessId: string, publicSlug = "") {
  const validSlug = /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(publicSlug);
  const result = new URL(validSlug ? `https://${publicSlug}.fideli.site` : publicClubUrl);
  if (!validSlug) result.searchParams.set("business", businessId);
  return result;
}

function customerQrPayload(customerId: string, cardId?: string | null, token?: string | null) {
  const value = new URL(`fideli://customer/${safeId(customerId)}`);
  if (cardId) value.searchParams.set("card", safeId(cardId));
  if (token) value.searchParams.set("token", token);
  return value.toString();
}
const googleIssuerId = Deno.env.get("GOOGLE_ISSUER_ID") || "";
const googleClassSuffix = Deno.env.get("GOOGLE_CLASS_SUFFIX") || "fideli_loyalty";
const googleLogoUrl = Deno.env.get("GOOGLE_LOGO_URL") || `${functionBaseUrl}/assets/icon.png`;

type Customer = {
  id: string; business_id: string; name: string; points: number; stamps: number;
  visits: number; tier: string; referral_code: string; wallet_message?: string | null;
  wallet_campaign_url?: string | null;
  deleted_at?: string | null;
  last_activity_at?: string | null;
  card_balances?: Record<string, { points?: number; stamps?: number; visits?: number }> | null;
  pwa_access_token?: string | null;
  pwa_device_token_hash?: string | null;
  pwa_claim_token_hash?: string | null;
  pwa_claim_expires_at?: string | null;
};

type BusinessLocation = {
  id?: string;
  name?: string;
  address?: string;
  latitude: number;
  longitude: number;
  radiusMeters?: number;
  message?: string;
};

function businessLocations(businessRow: Record<string, unknown>): BusinessLocation[] {
  if (!Array.isArray(businessRow.locations)) return [];
  return businessRow.locations.slice(0, 10).flatMap((raw) => {
    if (!raw || typeof raw !== "object") return [];
    const item = raw as Record<string, unknown>;
    const latitude = Number(item.latitude);
    const longitude = Number(item.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return [];
    return [{
      id: String(item.id || ""),
      name: String(item.name || "Sucursal"),
      address: String(item.address || ""),
      latitude,
      longitude,
      radiusMeters: Math.min(5000, Math.max(50, Number(item.radiusMeters) || 180)),
      message: String(item.message || "Estás cerca. Presenta tu tarjeta Fideli."),
    }];
  });
}

function googleMerchantLocations(businessRow: Record<string, unknown>) {
  return businessLocations(businessRow).map((item) => ({
    latitude: item.latitude,
    longitude: item.longitude,
  }));
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function phoneLookupCandidates(value: string) {
  const digits = value.replace(/\D/g, "").slice(0, 40);
  const candidates = new Set<string>();
  if (digits.length >= 7) candidates.add(digits);
  // El mismo numero boliviano suele escribirse con o sin +591/00591.
  const international = digits.startsWith("00") ? digits.slice(2) : digits;
  if (international.length >= 7) candidates.add(international);
  if (international.startsWith("591") && international.length === 11) {
    candidates.add(international.slice(3));
  } else if (international.length === 8) {
    candidates.add(`591${international}`);
  }
  return [...candidates];
}

async function customerByPhone(businessId: string, phone: string, columns = "*") {
  const candidates = phoneLookupCandidates(phone);
  if (!candidates.length) return { customer: null, found: false, ambiguous: false };
  const { data, error } = await admin
    .from("customers")
    .select(columns)
    .eq("business_id", businessId)
    .in("phone_normalized", candidates)
    .is("deleted_at", null)
    .limit(5);
  if (error) throw error;
  const unique = [...new Map((data || []).map((item) => [item.id, item])).values()];
  return {
    customer: unique.length === 1 ? unique[0] : null,
    found: unique.length > 0,
    ambiguous: unique.length > 1,
  };
}

function pwaRealtimeTopic(businessId: string, customerId: string, tokenHash: string, cardId = "") {
  const cardPart = cardId ? `-${safeId(cardId)}` : "";
  return `pwa-device-${safeId(businessId)}-${safeId(customerId)}${cardPart}-${tokenHash.slice(0, 32)}`;
}

async function authorizedPwaCustomer(
  req: Request,
  businessId: string,
  customerId: string,
  cardId = "",
) {
  const deviceToken = String(req.headers.get("x-fideli-device-token") || "");
  if (deviceToken.length < 32) return null;
  const tokenHash = await sha256Hex(deviceToken);
  if (cardId) {
    const { data: deviceLink } = await admin
      .from("customer_card_devices")
      .select("customer_id")
      .eq("business_id", businessId)
      .eq("customer_id", customerId)
      .eq("card_id", cardId)
      .eq("device_token_hash", tokenHash)
      .maybeSingle();
    if (deviceLink) {
      const { data } = await admin.from("customers")
        .select("*")
        .eq("business_id", businessId)
        .eq("id", customerId)
        .maybeSingle();
      return data || null;
    }
    const { data: enrollment } = await admin
      .from("customer_card_enrollments")
      .select("customer_id")
      .eq("business_id", businessId)
      .eq("customer_id", customerId)
      .eq("card_id", cardId)
      .eq("device_token_hash", tokenHash)
      .maybeSingle();
    if (enrollment) {
      const { data } = await admin.from("customers")
        .select("*")
        .eq("business_id", businessId)
        .eq("id", customerId)
        .maybeSingle();
      return data || null;
    }
  }
  const { data: linkedDevice } = await admin
    .from("customer_card_devices")
    .select("customer_id")
    .eq("business_id", businessId)
    .eq("customer_id", customerId)
    .eq("device_token_hash", tokenHash)
    .limit(1)
    .maybeSingle();
  if (linkedDevice) {
    const { data } = await admin.from("customers")
      .select("*")
      .eq("business_id", businessId)
      .eq("id", customerId)
      .maybeSingle();
    return data || null;
  }
  const { data: enrolledDevice } = await admin
    .from("customer_card_enrollments")
    .select("customer_id")
    .eq("business_id", businessId)
    .eq("customer_id", customerId)
    .eq("device_token_hash", tokenHash)
    .limit(1)
    .maybeSingle();
  if (enrolledDevice) {
    const { data } = await admin.from("customers")
      .select("*")
      .eq("business_id", businessId)
      .eq("id", customerId)
      .maybeSingle();
    return data || null;
  }
  const { data } = await admin.from("customers")
    .select("*")
    .eq("business_id", businessId)
    .eq("id", customerId)
    .eq("pwa_device_token_hash", tokenHash)
    .maybeSingle();
  return data || null;
}

async function linkCardToCustomerDevices(
  businessId: string,
  customerId: string,
  cardId: string,
  registrationDeviceHash: string | null,
) {
  const [{ data: enrollmentDevices }, { data: linkedDevices }] = await Promise.all([
    admin.from("customer_card_enrollments")
      .select("device_token_hash")
      .eq("business_id", businessId)
      .eq("customer_id", customerId)
      .not("device_token_hash", "is", null),
    admin.from("customer_card_devices")
      .select("device_token_hash")
      .eq("business_id", businessId)
      .eq("customer_id", customerId),
  ]);
  const deviceHashes = [...new Set([
    registrationDeviceHash || "",
    ...(enrollmentDevices || []).map((item) => String(item.device_token_hash || "")),
    ...(linkedDevices || []).map((item) => String(item.device_token_hash || "")),
  ].filter(Boolean))];
  if (!deviceHashes.length) return;
  const { error } = await admin.from("customer_card_devices").upsert(
    deviceHashes.map((deviceHash) => ({
      business_id: businessId,
      customer_id: customerId,
      card_id: cardId,
      device_token_hash: deviceHash,
      updated_at: new Date().toISOString(),
    })),
    { onConflict: "business_id,customer_id,card_id,device_token_hash" },
  );
  if (error) throw error;
}

type LoyaltyCard = {
  id: string; business_id: string; name: string; card_kind: string;
  program_type: string; earning_rate: number; goal: number; active: boolean;
  expires_at?: string | null;
  color_hex?: string | null; background_image_path?: string | null;
  stamp_icon?: string | null;
  wallet_layout?: string | null;
  welcome_message?: string | null;
  stamp_notification_message?: string | null;
  completion_message?: string | null;
  expiration_notice?: string | null;
  expiration_notice_key?: string | null;
  reward_milestones?: Array<{
    id?: string;
    stamp?: number;
    reward?: string;
    message?: string;
  }> | null;
  updated_at?: string | null;
};

type WalletPassRow = {
  customer_id?: string | null;
  card_id?: string | null;
  update_tag?: number | null;
  updated_at?: string | null;
};

function response(body: unknown, status = 200, extra: HeadersInit = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json; charset=utf-8", ...extra },
  });
}

function publicCardPayload(
  businessRow: Record<string, unknown>,
  cardRow: LoyaltyCard | null,
  customerRow?: Customer | null,
) {
  if (!cardRow) return null;
  const expired = Boolean(
    cardRow.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now(),
  );
  const values = customerRow ? googleCardValues(customerRow, cardRow) : {
    balance: 0,
    goal: Math.max(1, Number(cardRow.goal) || 1),
  };
  const selectedBalance = customerRow ? customerRow.card_balances?.[cardRow.id] : null;
  return {
    id: cardRow.id,
    name: cardRow.name,
    cardKind: cardRow.card_kind,
    programType: cardRow.program_type,
    goal: Math.max(1, Number(cardRow.goal) || 1),
    balance: Number(values.balance || 0),
    visits: Number(selectedBalance?.visits ?? customerRow?.visits ?? 0),
    colorHex: cardRow.color_hex || businessRow.color_hex || "#6750A4",
    stampIcon: cardRow.stamp_icon || "coffee",
    walletLayout: cardRow.wallet_layout || "poster",
    expiresAt: cardRow.expires_at || null,
    active: cardRow.active !== false && !expired,
    expired,
    expirationNotice: cardRow.expiration_notice || null,
    logoUrl: `${functionBaseUrl}/assets/pwa/logo/${safeId(String(businessRow.id || ""))}.png`,
    iconUrl: `${functionBaseUrl}/assets/google/logo/${safeId(String(businessRow.id || ""))}.png`,
    backgroundUrl: cardRow.background_image_path
      ? `${functionBaseUrl}/assets/pwa/background/${safeId(String(businessRow.id || ""))}/${safeId(cardRow.id)}.png?v=${encodeURIComponent(String(cardRow.updated_at || "1"))}`
      : null,
  };
}

function webPushConfigured() {
  return Boolean(Deno.env.get("WEB_PUSH_PUBLIC_KEY") && Deno.env.get("WEB_PUSH_PRIVATE_KEY"));
}

async function sendWebPush(
  businessId: string,
  customerIds: string[],
  title: string,
  body: string,
  targetUrl: string | null = null,
  cardId: string | null = null,
) {
  const publicKey = Deno.env.get("WEB_PUSH_PUBLIC_KEY") || "";
  const privateKey = Deno.env.get("WEB_PUSH_PRIVATE_KEY") || "";
  if (!publicKey || !privateKey || !customerIds.length) return;
  webpush.setVapidDetails(
    Deno.env.get("WEB_PUSH_SUBJECT") || "mailto:lucastejerina790@gmail.com",
    publicKey,
    privateKey,
  );
  const { data: subscriptions } = await admin
    .from("web_push_subscriptions")
    .select("id,customer_id,card_id,endpoint,p256dh,auth")
    .eq("business_id", businessId)
    .in("customer_id", customerIds);
  const matchingSubscriptions = ((subscriptions || []) as Array<{
    id: string; customer_id: string; card_id?: string | null;
    endpoint: string; p256dh: string; auth: string;
  }>);
  // Un mismo navegador puede conservar una suscripción por cada tarjeta.
  // La notificación, sin embargo, pertenece a la persona/dispositivo y debe
  // mostrarse una sola vez.
  const pushSubscriptions = [...new Map(
    matchingSubscriptions.map((subscription) => [subscription.endpoint, subscription]),
  ).values()];
  const businessRow = await business(businessId);
  await Promise.all(pushSubscriptions.map(async (subscription) => {
    try {
      let notificationUrl = targetUrl || publicClubUrl;
      if (!targetUrl) {
        const cardUrl = publicClubForBusiness(businessId, String(businessRow.public_slug || ""));
        if (cardId || subscription.card_id) cardUrl.searchParams.set("card", cardId || subscription.card_id!);
        cardUrl.searchParams.set("customer", subscription.customer_id);
        notificationUrl = cardUrl.toString();
      }
      await webpush.sendNotification({
        endpoint: subscription.endpoint,
        keys: { p256dh: subscription.p256dh, auth: subscription.auth },
      }, JSON.stringify({
        title,
        body,
        url: notificationUrl,
        icon: `${functionBaseUrl}/assets/google/logo/${businessId}.png`,
        tag: `fideli-${businessId}-${subscription.customer_id}-${cardId || "general"}`,
      }));
    } catch (error) {
      const statusCode = Number((error as { statusCode?: number }).statusCode || 0);
      if (statusCode === 404 || statusCode === 410) {
        await admin.from("web_push_subscriptions").delete().eq("id", subscription.id);
      } else {
        console.error("PWA push failed", error);
      }
    }
  }));
}

async function broadcastPwaCardUpdate(
  businessId: string,
  customerIds: string[] | null = null,
  reason = "updated",
) {
  if (customerIds && customerIds.length === 0) return;
  let query = admin
    .from("customers")
    .select("id,pwa_device_token_hash")
    .eq("business_id", businessId);
  if (customerIds) query = query.in("id", customerIds);
  let enrollmentQuery = admin
    .from("customer_card_enrollments")
    .select("customer_id,card_id,device_token_hash")
    .eq("business_id", businessId);
  if (customerIds) enrollmentQuery = enrollmentQuery.in("customer_id", customerIds);
  let deviceQuery = admin
    .from("customer_card_devices")
    .select("customer_id,card_id,device_token_hash")
    .eq("business_id", businessId);
  if (customerIds) deviceQuery = deviceQuery.in("customer_id", customerIds);
  const [
    { data, error },
    { data: enrollments, error: enrollmentError },
    { data: linkedDevices, error: deviceError },
  ] = await Promise.all([
    query,
    enrollmentQuery,
    deviceQuery,
  ]);
  if (error) throw error;
  if (enrollmentError) throw enrollmentError;
  if (deviceError) throw deviceError;
  const legacyMessages = (data || [])
    .filter((item) => item.pwa_device_token_hash)
    .map((item) => ({
      topic: pwaRealtimeTopic(businessId, String(item.id), String(item.pwa_device_token_hash)),
      event: "card_updated",
      payload: { reason },
    }));
  const enrollmentMessages = (enrollments || [])
    .filter((item) => item.device_token_hash)
    .map((item) => ({
      topic: pwaRealtimeTopic(
        businessId,
        String(item.customer_id),
        String(item.device_token_hash),
        String(item.card_id),
      ),
      event: "card_updated",
      payload: { reason },
    }));
  const deviceMessages = (linkedDevices || [])
    .filter((item) => item.device_token_hash)
    .map((item) => ({
      topic: pwaRealtimeTopic(
        businessId,
        String(item.customer_id),
        String(item.device_token_hash),
        String(item.card_id),
      ),
      event: "card_updated",
      payload: { reason },
    }));
  const messages = [...new Map(
    [...legacyMessages, ...enrollmentMessages, ...deviceMessages].map((item) => [item.topic, item]),
  ).values()];
  for (let offset = 0; offset < messages.length; offset += 100) {
    const result = await fetch(`${supabaseUrl}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: {
        apikey: serviceRole,
        authorization: `Bearer ${serviceRole}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ messages: messages.slice(offset, offset + 100) }),
    });
    if (!result.ok) {
      console.error("PWA realtime broadcast failed", result.status, await result.text());
    }
  }
}

async function broadcastPwaTopicUpdate(topic: string, reason = "updated") {
  if (!topic) return;
  const result = await fetch(`${supabaseUrl}/realtime/v1/api/broadcast`, {
    method: "POST",
    headers: {
      apikey: serviceRole,
      authorization: `Bearer ${serviceRole}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      messages: [{ topic, event: "card_updated", payload: { reason } }],
    }),
  });
  if (!result.ok) {
    console.error("PWA direct realtime broadcast failed", result.status, await result.text());
  }
}

// Apple only shows a Wallet change notification when a field's value really
// changes. This invisible revision lets an intentionally repeated campaign
// notify again without showing technical text to the customer.
function walletNotificationValue(message: string) {
  const revision = Date.now().toString(2)
    .split("")
    .map((bit) => bit === "1" ? "\u200c" : "\u200b")
    .join("");
  return `${message}${revision}`;
}

function cardProgressValue(cardRow: LoyaltyCard, customerRow: Customer) {
  const balance = customerRow.card_balances?.[cardRow.id];
  const usesPoints = cardRow.program_type === "points";
  const usesVisits = cardRow.program_type === "visits" || cardRow.program_type === "membership";
  return Number(
    usesPoints
      ? balance?.points ?? customerRow.points
      : usesVisits
      ? balance?.visits ?? customerRow.visits
      : balance?.stamps ?? customerRow.stamps,
  ) || 0;
}

function cardProgressMessage(
  cardRow: LoyaltyCard,
  customerRow: Customer,
  previousCustomerRow?: Customer | null,
  previousValueOverride?: number | null,
) {
  if (
    cardRow.card_kind === "Tarjeta de regalo" ||
    cardRow.program_type === "membership"
  ) {
    return "";
  }
  const goal = Math.max(1, Number(cardRow.goal) || 1);
  const value = cardProgressValue(cardRow, customerRow);
  const previousValue = Number.isFinite(previousValueOverride)
    ? Number(previousValueOverride)
    : previousCustomerRow
    ? cardProgressValue(cardRow, previousCustomerRow)
    : value;
  const remaining = Math.max(0, goal - value);
  const milestones = cardRow.reward_milestones || [];
  // Si el comercio suma varios sellos juntos, no se pierde un premio
  // intermedio: se anuncia el último hito cruzado en ese movimiento.
  const crossedMilestone = value > previousValue
    ? [...milestones]
      .filter((item) => Number(item.stamp) > previousValue && Number(item.stamp) <= value)
      .sort((left, right) => Number(right.stamp) - Number(left.stamp))[0]
    : null;
  const milestone = crossedMilestone ||
    (!previousCustomerRow
      ? milestones.find((item) => Number(item.stamp) === value) ||
        (value >= goal ? milestones.find((item) => Number(item.stamp) === goal) : null)
      : null);
  const reachedGoalNow = value >= goal &&
    (!previousCustomerRow || previousValue < goal);
  const savedMilestoneMessage = milestone?.message?.trim() || "";
  const isLegacyMilestoneMessage = /^¡?Llegaste al sello\s+\d+!/i.test(savedMilestoneMessage);
  const template = milestone
    ? (!savedMilestoneMessage || isLegacyMilestoneMessage
      ? "¡Ganaste {premio}!"
      : savedMilestoneMessage)
    : (reachedGoalNow
      ? cardRow.completion_message?.trim() || "🎉 ¡Completaste tu tarjeta! Tu recompensa está lista."
      : cardRow.stamp_notification_message?.trim() || "¡Ya tienes {sellos} sellos! Sigue así.");
  return template
    .replaceAll("{nombre}", customerRow.name)
    .replaceAll("{sellos}", String(value))
    .replaceAll("{puntos}", String(value))
    .replaceAll("{visitas}", String(value))
    .replaceAll("{valor}", String(value))
    .replaceAll("{meta}", String(goal))
    .replaceAll("{faltan}", String(remaining))
    .replaceAll("{premio}", milestone?.reward?.trim() || "tu premio");
}

function htmlResponse(html: string, status = 200) {
  return new Response(html, {
    status,
    headers: {
      ...cors,
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function clubLayout(title: string, color: string, content: string) {
  const safeColor = /^#[0-9a-f]{6}$/i.test(color) ? color : "#6750A4";
  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} · Fideli</title><style>
*{box-sizing:border-box}body{margin:0;background:#f7f3fb;color:#211b24;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.wrap{max-width:520px;margin:0 auto;padding:32px 20px}.brand{font-weight:800;letter-spacing:.08em;margin-bottom:28px}
.card{background:#fff;border-radius:24px;padding:28px;box-shadow:0 12px 40px #291c3314}.hero{width:64px;height:64px;border-radius:18px;background:${safeColor};display:grid;place-items:center;color:#fff;font-size:30px}
h1{font-size:30px;line-height:1.1;margin:20px 0 10px}p{line-height:1.5;color:#625866}label{display:block;font-weight:650;margin:18px 0 7px}
input{width:100%;padding:14px 15px;border:1px solid #d7ceda;border-radius:12px;font:inherit}button,.button{display:block;width:100%;margin-top:22px;border:0;border-radius:14px;padding:15px;background:${safeColor};color:#fff;font-weight:750;font-size:17px;text-align:center;text-decoration:none}
.secondary{background:#eee8f0;color:#332a36}.code{text-align:center;font-size:22px;font-weight:800;letter-spacing:.08em}.fine{font-size:13px;text-align:center;margin-top:20px}.hidden{position:absolute;left:-9999px}
</style></head><body><main class="wrap"><div class="brand">FIDELI</div><section class="card">${content}</section></main></body></html>`;
}

function safeId(value: string) {
  return decodeURIComponent(value).replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 80);
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function expectedPassToken(serial: string) {
  return await sha256(`${serial}:${teamId}`);
}

async function appleAuthorized(req: Request, serial: string) {
  return req.headers.get("authorization") === `ApplePass ${await expectedPassToken(serial)}`;
}

async function merchantUser(req: Request) {
  const authorization = req.headers.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) return null;
  const client = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser();
  return error ? null : data.user;
}

function hexToRgb(hex: string) {
  const clean = /^#[0-9a-fA-F]{6}$/.test(hex) ? hex.slice(1) : "6750A4";
  const values = [0, 2, 4].map((start) => Number.parseInt(clean.slice(start, start + 2), 16));
  return `rgb(${values[0]}, ${values[1]}, ${values[2]})`;
}

async function customer(serial: string): Promise<Customer | null> {
  const { data } = await admin.from("customers").select("*").eq("id", serial).maybeSingle();
  return data as Customer | null;
}

async function business(businessId: string) {
  const { data } = await admin.from("businesses").select("*").eq("id", businessId).single();
  return data;
}

async function walletArtwork(folder?: string | null, backgroundFolder?: string | null, logoFolder?: string | null) {
  const artwork: Record<string, Buffer> = {
    "icon.png": icon,
    "icon@2x.png": icon2x,
  };
  if (folder) {
    for (const name of ["icon.png", "icon@2x.png", "icon@3x.png"]) {
      const { data, error } = await admin.storage
        .from("business-assets")
        .download(`${folder}/${name}`);
      if (!error && data) artwork[name] = Buffer.from(await data.arrayBuffer());
    }
  }
  if (logoFolder) {
    for (const name of ["logo.png", "logo@2x.png", "logo@3x.png"]) {
      const { data, error } = await admin.storage
        .from("business-assets")
        .download(`${logoFolder}/${name}`);
      if (!error && data) artwork[name] = Buffer.from(await data.arrayBuffer());
    }
  }
  if (backgroundFolder) {
    // Keep only one source image in memory. Loading all three large poster
    // variants can exceed the Edge Function memory limit during pass updates.
    for (const name of ["strip@2x.png", "strip.png", "strip@3x.png"]) {
      const { data, error } = await admin.storage
        .from("business-assets")
        .download(`${backgroundFolder}/${name}`);
      if (!error && data) {
        artwork["source-background.png"] = Buffer.from(await data.arrayBuffer());
        break;
      }
    }
  }
  if (!artwork["logo.png"] && artwork["icon.png"]) artwork["logo.png"] = artwork["icon.png"];
  if (!artwork["logo@2x.png"] && artwork["icon@2x.png"]) artwork["logo@2x.png"] = artwork["icon@2x.png"];
  if (!artwork["logo@3x.png"] && artwork["icon@3x.png"]) artwork["logo@3x.png"] = artwork["icon@3x.png"];
  return artwork;
}

function renderCover(source: Buffer, width: number, height: number) {
  return ImageMagick.read(source, (image) => {
    const geometry = new MagickGeometry(width, height);
    geometry.fillArea = true;
    image.resize(geometry);
    image.crop(width, height, Gravity.Center);
    image.resetPage();
    return image.write(MagickFormat.Png, (bytes) => Buffer.from(bytes));
  });
}

function drawStamp(
  type: string,
  x: number,
  y: number,
  scale: number,
  opacity: number,
  image: IMagickImage,
  color = "255,255,255",
  baseStrokeWidth = 3,
) {
  const px = (value: number) => (x + value) * scale;
  const py = (value: number) => (y + value) * scale;
  const illustrated = opacity >= 0.8
    ? illustratedStampPngActive[type]
    : illustratedStampPngInactive[type];
  const phosphor = opacity >= 0.8
    ? (phosphorStampPngActive[type] || phosphorStampPngActive.coffee)
    : (phosphorStampPngInactive[type] || phosphorStampPngInactive.coffee);
  const stampPng = illustrated || phosphor;
  if (stampPng) {
    ImageMagick.read(Buffer.from(stampPng, "base64"), (iconImage) => {
      iconImage.resize(44 * scale, 44 * scale);
      image.composite(
        iconImage,
        CompositeOperator.Over,
        new Point(px(0), py(0)),
      );
    });
    return;
  }
  // Apple Wallet rasteriza estos símbolos dentro del arte del pase. Usamos
  // siluetas gruesas y rellenas para que coincidan con la vista previa de la
  // app y sigan siendo visibles aun cuando Wallet reduzca la imagen.
  const stampColor = color === "0,0,0"
    ? "rgb(24,24,24)"
    : `rgb(${Math.round(255 * (0.45 + opacity * 0.55))},${Math.round(255 * (0.45 + opacity * 0.55))},${Math.round(255 * (0.45 + opacity * 0.55))})`;
  const draw = new Drawables()
    .strokeColor(new MagickColor(stampColor))
    .strokeWidth(Math.max(baseStrokeWidth, 5) * scale)
    .fillColor(MagickColors.Transparent);
  const solid = new Drawables()
    .strokeColor(new MagickColor(stampColor))
    .strokeWidth(0)
    .fillColor(new MagickColor(stampColor));
  const line = (x1: number, y1: number, x2: number, y2: number) => draw.line(px(x1), py(y1), px(x2), py(y2));
  switch (type) {
    case "pizza":
      // Cuña compacta: los trazos gruesos forman una silueta reconocible.
      draw.strokeWidth(9 * scale);
      line(10, 35, 22, 8); line(22, 8, 37, 34); line(11, 34, 37, 34);
      draw.strokeWidth(5 * scale).point(px(21), py(21)).point(px(29), py(27));
      break;
    case "haircut":
      draw.strokeWidth(5 * scale);
      line(12, 31, 34, 7); line(33, 31, 11, 8);
      solid
        .roundRectangle(px(5), py(29), px(15), py(39), 5 * scale, 5 * scale)
        .roundRectangle(px(31), py(29), px(41), py(39), 5 * scale, 5 * scale);
      solid.draw(image);
      break;
    case "star": {
      const points = [[22, 5], [27, 16], [39, 17], [30, 25], [33, 37], [22, 31], [11, 37], [14, 25], [5, 17], [17, 16], [22, 5]];
      draw.strokeWidth(8 * scale);
      for (let i = 0; i < points.length - 1; i++) line(points[i][0], points[i][1], points[i + 1][0], points[i + 1][1]);
      break;
    }
    case "heart": {
      const points = [[22, 38], [8, 27], [6, 16], [11, 9], [18, 10], [22, 15], [26, 10], [34, 9], [39, 16], [36, 27], [22, 38]];
      draw.strokeWidth(9 * scale);
      for (let i = 0; i < points.length - 1; i++) line(points[i][0], points[i][1], points[i + 1][0], points[i + 1][1]);
      break;
    }
    case "paw": {
      // Use filled rounded shapes instead of point strokes. The WASM renderer
      // used by Supabase can discard isolated point primitives in signed PNGs.
      const paw = new Drawables()
        .fillColor(new MagickColor(stampColor))
        .strokeColor(new MagickColor(stampColor))
        .strokeWidth(0)
        .roundRectangle(px(12), py(21), px(32), py(39), 8 * scale, 8 * scale)
        .roundRectangle(px(5), py(12), px(13), py(22), 4 * scale, 4 * scale)
        .roundRectangle(px(14), py(5), px(22), py(16), 4 * scale, 4 * scale)
        .roundRectangle(px(24), py(5), px(32), py(16), 4 * scale, 4 * scale)
        .roundRectangle(px(34), py(12), px(42), py(22), 4 * scale, 4 * scale);
      paw.draw(image);
      return;
    }
    case "check":
      draw.strokeWidth(8 * scale); line(7, 23, 17, 33); line(17, 33, 38, 10);
      break;
    default:
      // Taza rellena con asa y vapor, similar al icono mostrado en Flutter.
      solid
        .roundRectangle(px(8), py(15), px(34), py(35), 4 * scale, 4 * scale)
        .roundRectangle(px(31), py(19), px(42), py(31), 5 * scale, 5 * scale)
        .roundRectangle(px(6), py(36), px(37), py(40), 2 * scale, 2 * scale);
      solid.draw(image);
      draw.strokeWidth(4 * scale);
      line(15, 12, 15, 4); line(23, 12, 23, 4); line(31, 12, 31, 4);
  }
  draw.draw(image);
}

function renderStampStrip(
  type: string,
  earned: number,
  goal: number,
  scale: number,
  background?: Buffer,
) {
  const visibleGoal = Math.min(Math.max(goal, 1), 15);
  const columns = visibleGoal <= 8 ? Math.min(4, visibleGoal) : 5;
  const rows = Math.ceil(visibleGoal / columns);
  const cellWidth = 325 / columns;
  const startY = rows === 1 ? 39 : 15;
  const render = (image: IMagickImage) => {
    const targetWidth = 375 * scale;
    const targetHeight = 123 * scale;
    const cover = new MagickGeometry(targetWidth, targetHeight);
    cover.fillArea = true;
    image.resize(cover);
    image.crop(targetWidth, targetHeight, Gravity.Center);
    image.resetPage();
    for (let index = 0; index < visibleGoal; index++) {
      const row = Math.floor(index / columns);
      const itemsInRow = Math.min(columns, visibleGoal - row * columns);
      const rowWidth = itemsInRow * cellWidth;
      const x = (375 - rowWidth) / 2 + (index % columns) * cellWidth + (cellWidth - 44) / 2;
      const y = startY + row * 57;
      drawStamp(type, x, y, scale, index < earned ? 1 : 0.28, image);
    }
    return image.write(MagickFormat.Png, (data) => Buffer.from(data));
  };
  return background
    ? ImageMagick.read(background, render)
    : ImageMagick.read(MagickColors.Transparent, 375 * scale, 123 * scale, render);
}

function renderStampPoster(
  type: string,
  earned: number,
  goal: number,
  scale: number,
  colorHex: string,
  background?: Buffer,
  headerLogo?: Buffer,
) {
  const visibleGoal = Math.min(Math.max(goal, 1), 15);
  const columns = visibleGoal <= 8 ? Math.min(4, visibleGoal) : 5;
  const rows = Math.ceil(visibleGoal / columns);
  const cellWidth = 285 / columns;
  // Poster Generic reserves the center for its QR. Keep the stamp progress
  // in the clear artwork area between the logo/header and the barcode.
  const startY = rows === 1 ? 144 : 110;
  const render = (image: IMagickImage) => {
    const targetWidth = 345 * scale;
    const targetHeight = 505 * scale;
    const cover = new MagickGeometry(targetWidth, targetHeight);
    cover.fillArea = true;
    image.resize(cover);
    image.crop(targetWidth, targetHeight, Gravity.Center);
    image.resetPage();
    if (background) {
      const shade = new Drawables()
        .fillColor(new MagickColor("rgba(0,0,0,0.36)"))
        .rectangle(0, 0, 345 * scale, 505 * scale);
      shade.draw(image);
    }
    // Poster Generic limits primaryLogo to 126 x 30 pt. Drawing the merchant
    // logo into the poster artwork lets it use a larger, still crisp area.
    if (headerLogo) {
      ImageMagick.read(headerLogo, (logoImage) => {
        logoImage.resize(214 * scale, 42 * scale);
        image.composite(
          logoImage,
          CompositeOperator.Over,
          new Point(16 * scale, 26 * scale),
        );
      });
    }
    for (let index = 0; index < visibleGoal; index++) {
      const row = Math.floor(index / columns);
      const itemsInRow = Math.min(columns, visibleGoal - row * columns);
      const rowWidth = itemsInRow * cellWidth;
      const x = (345 - rowWidth) / 2 + (index % columns) * cellWidth + (cellWidth - 44) / 2;
      const y = startY + row * 62;
      const opacity = index < earned ? 1 : 0.34;
      drawStamp(type, x, y, scale, opacity, image);
    }
    return image.write(MagickFormat.Png, (data) => Buffer.from(data));
  };
  return background
    ? ImageMagick.read(background, render)
    : ImageMagick.read(new MagickColor(colorHex), 345 * scale, 505 * scale, render);
}

async function loyaltyCard(businessId: string, cardId?: string | null): Promise<LoyaltyCard | null> {
  let query = admin.from("loyalty_cards").select("*")
    .eq("business_id", businessId)
    .neq("card_kind", "Evento");
  if (cardId) query = query.eq("id", cardId);
  else query = query.eq("active", true).order("created_at", { ascending: true }).limit(1);
  const { data } = await query.maybeSingle();
  return data as LoyaltyCard | null;
}

async function walletPassSerialsForCard(
  businessId: string,
  customerId: string,
  cardId: string,
) {
  const [defaultCard, { data: passes, error }] = await Promise.all([
    loyaltyCard(businessId),
    admin.from("wallet_passes")
      .select("serial_number,card_id")
      .eq("business_id", businessId)
      .or(`customer_id.eq.${customerId},serial_number.eq.${customerId}`),
  ]);
  if (error) throw error;
  return (passes || [])
    .filter((pass) =>
      pass.card_id === cardId ||
      (pass.card_id == null && pass.serial_number === customerId && defaultCard?.id === cardId)
    )
    .map((pass) => pass.serial_number as string);
}

function registrationCategory(cardRow: LoyaltyCard | null) {
  if (!cardRow) return "stamps";
  if (cardRow.card_kind === "Tarjeta de regalo") return "gift";
  if (cardRow.program_type === "membership") return "membership";
  if (cardRow.program_type === "points" || cardRow.program_type === "hybrid") return "points";
  return "stamps";
}

function registrationCategoryName(cardRow: LoyaltyCard | null) {
  const category = registrationCategory(cardRow);
  if (category === "membership") return "una membresía";
  if (category === "gift") return "una tarjeta de regalo";
  if (category === "points") return "una tarjeta de puntos";
  return "una tarjeta de sellos";
}

function isProtectedPersonalCard(cardRow: LoyaltyCard | null) {
  return Boolean(
    cardRow &&
      (cardRow.card_kind === "Tarjeta de regalo" || cardRow.program_type === "membership"),
  );
}

async function qrTokenForCard(customerRow: Customer, cardRow: LoyaltyCard | null) {
  if (!cardRow || !isProtectedPersonalCard(cardRow)) {
    return customerRow.pwa_access_token || null;
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(serviceRole),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(
      `fideli-private-card-v1:${customerRow.business_id}:${customerRow.id}:${cardRow.id}`,
    ),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function registrationConflict(
  businessId: string,
  customerId: string | null | undefined,
  selectedCard: LoyaltyCard | null,
) {
  if (!selectedCard || !customerId) {
    return { duplicateCard: false, duplicateCategory: false };
  }
  const { data: enrollments } = await admin
    .from("customer_card_enrollments")
    .select("card_id,category")
    .eq("business_id", businessId)
    .eq("customer_id", customerId);
  const duplicateCard = (enrollments || []).some((item) => item.card_id === selectedCard.id);
  const duplicateCategory = (enrollments || []).some(
    (item) => item.category === registrationCategory(selectedCard),
  );
  return { duplicateCard, duplicateCategory: !duplicateCard && duplicateCategory };
}

async function passContext(serial: string) {
  const { data: passRow } = await admin
    .from("wallet_passes")
    .select("customer_id,card_id,update_tag,updated_at")
    .eq("serial_number", serial)
    .maybeSingle();
  const walletPass = passRow as WalletPassRow | null;
  const customerId = walletPass?.customer_id || serial;
  const customerRow = await customer(customerId);
  if (!customerRow) return null;
  const cardRow = await loyaltyCard(customerRow.business_id, walletPass?.card_id);
  return { customerRow, cardRow, walletPass };
}

async function createPass(customerRow: Customer, serialNumber = customerRow.id, cardRow: LoyaltyCard | null = null) {
  const businessRow = await business(customerRow.business_id);
  const { data: customerEnrollments } = await admin.from("customer_card_enrollments")
    .select("card_id")
    .eq("business_id", customerRow.business_id)
    .eq("customer_id", customerRow.id);
  const enrolledIds = [...new Set((customerEnrollments || []).map((item) => String(item.card_id)))];
  const { data: enrolledCards } = enrolledIds.length
    ? await admin.from("loyalty_cards").select("id,name,active,expires_at")
      .eq("business_id", customerRow.business_id)
      .in("id", enrolledIds)
      .neq("card_kind", "Evento")
    : { data: [] };
  const relatedCardsSummary = (enrolledCards || []).map((item) => {
    const relatedExpired = Boolean(
      item.expires_at && new Date(item.expires_at).getTime() <= Date.now(),
    );
    return `${item.name} · ${item.active === false || relatedExpired ? "Inactiva" : "Activa"}`;
  }).join("\n");
  const authenticationToken = await expectedPassToken(serialNumber);
  const goal = Math.max(1, cardRow?.goal || 7);
  const selectedBalance = cardRow ? customerRow.card_balances?.[cardRow.id] : null;
  const points = Number(selectedBalance?.points ?? customerRow.points) || 0;
  const stamps = Number(selectedBalance?.stamps ?? customerRow.stamps) || 0;
  const visits = Number(selectedBalance?.visits ?? customerRow.visits) || 0;
  const usesPoints = cardRow?.program_type === "points";
  const usesVisits = cardRow?.program_type === "visits" || cardRow?.program_type === "membership";
  const isGift = cardRow?.card_kind === "Tarjeta de regalo";
  const isMembership = cardRow?.program_type === "membership";
  const progressValue = usesPoints ? points : usesVisits ? visits : stamps;
  const remaining = Math.max(0, goal - progressValue);
  const expired = Boolean(cardRow?.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now());
  const voided = Boolean(customerRow.deleted_at) || cardRow?.active === false || expired;
  const isStampCard = !usesPoints && !usesVisits && !isGift;
  const usesPosterLayout = isStampCard && cardRow?.wallet_layout !== "classic";
  const usesFullBackground = !isStampCard && cardRow?.wallet_layout !== "classic";
  const cardColor = cardRow?.color_hex || businessRow.color_hex || "#6750A4";
  const artwork = await walletArtwork(
    businessRow.wallet_icon_path,
    cardRow?.background_image_path,
    businessRow.wallet_logo_path,
  );
  const background = artwork["source-background.png"];
  delete artwork["source-background.png"];
  if (isStampCard) {
    await ensureImageMagick();
    // Wallet accepts a high-resolution base asset. Rendering one poster and
    // one legacy strip avoids six simultaneous ImageMagick allocations.
    artwork["strip.png"] = renderStampStrip(cardRow?.stamp_icon || "coffee", stamps, goal, 2, background);
    if (usesPosterLayout) {
      artwork["background.png"] = renderStampPoster(
        cardRow?.stamp_icon || "coffee",
        stamps,
        goal,
        2,
        cardColor,
        background,
        artwork["logo@2x.png"] || artwork["logo.png"],
      );
    }
  } else {
    if (background) {
      await ensureImageMagick();
      if (usesFullBackground) {
        artwork["background.png"] = renderCover(background, 180, 220);
        artwork["background@2x.png"] = renderCover(background, 360, 440);
      } else {
        artwork["strip.png"] = renderCover(background, 375, 123);
        artwork["strip@2x.png"] = renderCover(background, 750, 246);
      }
    }
  }

  const expiration = cardRow?.expires_at
    ? new Date(cardRow.expires_at).toLocaleDateString("es")
    : "SIN VENCIMIENTO";
  const headerFields: Record<string, unknown>[] = [];
  const primaryFields: Record<string, unknown>[] = [];
  const secondaryFields: Record<string, unknown>[] = [];

  if (isGift) {
    primaryFields.push({
      key: "balance",
      label: "SALDO",
      value: `🎁  Bs ${points}`,
      changeMessage: "Tu saldo ahora es %@",
    });
    if (cardRow?.expires_at) {
      secondaryFields.push({ key: "expiration", label: "VENCIMIENTO", value: expiration });
    }
  } else if (isMembership) {
    primaryFields.push({
      key: "membershipStatus",
      label: "MEMBRESÍA",
      value: voided ? "INACTIVA" : "ACTIVA",
      changeMessage: "Tu membresía está %@",
    });
    secondaryFields.push({ key: "expiration", label: "VENCIMIENTO", value: expiration });
  } else {
    headerFields.push({
      key: "reward",
      label: usesPoints ? "RECOMPENSA" : "SELLOS",
      value: usesPoints
        ? (remaining === 0 ? "COMPLETA" : `FALTAN ${remaining}`)
        : `${Math.min(stamps, goal)}/${goal}`,
    });
    // A blank primary field still occupies a large row in Apple Wallet.  That
    // row was colliding with the second line of stamp artwork.  Stamp progress
    // already lives in the header and in strip.png, so only point cards need a
    // primary value here.
    if (usesPoints) {
      primaryFields.push({
        key: "points",
        label: "PUNTOS",
        value: `${progressValue} / ${goal}`,
      });
    }
    secondaryFields.push(
      { key: "member", label: "CLIENTE", value: customerRow.name },
      {
        key: "visits",
        label: "VISITAS",
        value: visits,
      },
    );
  }
  const campaignActionField = customerRow.wallet_campaign_url
    ? {
        key: "campaign-action",
        label: "PROMOCIÓN",
        value: "VER PROMOCIÓN →",
        attributedValue: `<a href="${customerRow.wallet_campaign_url}">VER PROMOCIÓN →</a>`,
      }
    : null;
  const backFields = [
    ...(relatedCardsSummary
      ? [{
          key: "fideliCards",
          label: `MIS TARJETAS (${enrolledIds.length})`,
          value: relatedCardsSummary,
          changeMessage: "Tus tarjetas Fideli se actualizaron: %@",
        }]
      : []),
    ...(cardRow?.expiration_notice?.trim()
      ? [{
          key: "expirationNotice",
          label: "AVISO",
          value: cardRow.expiration_notice.trim(),
          changeMessage: "%@",
        }]
      : []),
    ...(cardRow?.welcome_message?.trim()
      ? [{
          key: "welcome",
          label: "BIENVENIDA",
          value: cardRow.welcome_message
            .trim()
            .replaceAll("{nombre}", customerRow.name),
        }]
      : []),
    {
      key: "campaign",
      label: "Novedades del local",
      value: customerRow.wallet_message?.trim() || "Aquí recibirás las novedades y promociones del local.",
      changeMessage: "%@",
    },
    ...(customerRow.wallet_campaign_url
      ? [{
          key: "campaign-link",
          label: "PROMOCIÓN",
          value: "Ver promoción",
          attributedValue: `<a href="${customerRow.wallet_campaign_url}">Ver promoción</a>`,
        }]
      : []),
    { key: "card", label: "Tarjeta", value: `${cardRow?.card_kind || "Fidelización"}${cardRow?.expires_at ? ` · vence ${new Date(cardRow.expires_at).toLocaleDateString("es")}` : ""}` },
    {
      key: "benefit",
      label: isGift ? "Cómo funciona el saldo" : isMembership ? "Tu membresía" : "Tu recompensa",
      value: isGift
        ? "El comercio puede cargar o consumir dinero de esta tarjeta de regalo."
        : isMembership
        ? "Presenta esta tarjeta para validar que tu membresía está vigente."
        : usesPoints
        ? `Acumula ${goal} puntos para completar el beneficio.`
        : `Completa ${goal} sellos para obtener el beneficio.`,
    },
    { key: "terms", label: "Cómo usarla", value: "Presenta este pase en el comercio. El vendedor escaneará el QR y registrará tu sello y visita." },
  ];
  const pass = new PKPass(
    artwork,
    {
      wwdr: Deno.env.get("APPLE_WWDR_CERT_PEM")!,
      signerCert: Deno.env.get("APPLE_SIGNER_CERT_PEM")!,
      signerKey: Deno.env.get("APPLE_SIGNER_KEY_PEM")!,
    },
    {
      formatVersion: 1,
      passTypeIdentifier: passTypeId,
      serialNumber,
      teamIdentifier: teamId,
      organizationName: businessRow.name,
      description: `${cardRow?.name || "Tarjeta de fidelidad"} de ${businessRow.name}`,
      foregroundColor: "rgb(255, 255, 255)",
      labelColor: "rgb(255, 255, 255)",
      backgroundColor: hexToRgb(cardColor),
      webServiceURL: functionBaseUrl,
      authenticationToken,
      ...(businessLocations(businessRow).length
        ? {
            locations: businessLocations(businessRow).map((item) => ({
              latitude: item.latitude,
              longitude: item.longitude,
              relevantText: item.message || `Estás cerca de ${businessRow.name}`,
            })),
            maxDistance: Math.max(...businessLocations(businessRow).map((item) => item.radiusMeters || 180)),
          }
        : {}),
      // El pase personal no se comparte en regalo o membresía.
      // Esto no afecta al QR comercial del programa usado para inscribir.
      sharingProhibited: isGift || isMembership,
      // Changing artwork alone can otherwise look identical to an intermediary
      // cache. Keep the saved design revision inside pass.json so every Wallet
      // Studio save produces a verifiably different signed package.
      userInfo: {
        designRevision: cardRow?.updated_at || "default",
        designStampIcon: cardRow?.stamp_icon || "coffee",
        stampArtworkVersion: "wallet-stamps-illustrated-v4",
        designBackground: cardRow?.background_image_path || "",
        designLayout: cardRow?.wallet_layout || "poster",
        businessRevision: businessRow.updated_at || "default",
        businessWalletIcon: businessRow.wallet_icon_path || "",
        businessWalletLogo: businessRow.wallet_logo_path || "",
      },
      ...(voided ? { voided: true } : {}),
    },
  );
  if (cardRow?.expires_at) pass.setExpirationDate(new Date(cardRow.expires_at));
  // Do not give a membership/gift card the event-ticket notch merely because
  // Wallet Studio is set to poster mode.  Event-ticket is only useful when an
  // actual full-background image exists; without one it rearranges the fields
  // and makes Wallet disagree with the PWA preview.
  const storeCard = new PassType(usesFullBackground && Boolean(background) ? "eventTicket" : "storeCard");
  storeCard.headerFields.push(...headerFields);
  storeCard.primaryFields.push(...primaryFields);
  storeCard.secondaryFields.push(...secondaryFields);
  if (campaignActionField && !isGift && !isMembership) {
    storeCard.auxiliaryFields.push(campaignActionField);
  }
  storeCard.backFields.push(...backFields);
  pass.types.push(storeCard);
  if (!voided) {
    pass.setBarcodes({
      format: "PKBarcodeFormatQR",
      message: customerQrPayload(customerRow.id, cardRow?.id, await qrTokenForCard(customerRow, cardRow)),
      messageEncoding: "iso-8859-1",
      altText: customerRow.referral_code,
    });
  }
  return pass.getAsBuffer();
}

function base64Url(bytes: Uint8Array | string) {
  const input = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  return Buffer.from(input).toString("base64url");
}

type GoogleCredentials = { client_email: string; private_key: string };

function googleCardValues(customerRow: Customer, cardRow: LoyaltyCard | null) {
  const selectedBalance = cardRow ? customerRow.card_balances?.[cardRow.id] : null;
  const usesPoints = cardRow?.program_type === "points";
  const usesVisits = cardRow?.program_type === "visits" || cardRow?.program_type === "membership";
  const balance = Number(
    usesPoints
      ? selectedBalance?.points ?? customerRow.points
      : usesVisits
      ? selectedBalance?.visits ?? customerRow.visits
      : selectedBalance?.stamps ?? customerRow.stamps,
  ) || 0;
  const goal = Math.max(1, Number(cardRow?.goal) || 7);
  const isGift = cardRow?.card_kind === "Tarjeta de regalo";
  const isMembership = cardRow?.program_type === "membership";
  const expired = Boolean(cardRow?.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now());
  const inactive = Boolean(customerRow.deleted_at) || cardRow?.active === false || expired;
  const expiration = cardRow?.expires_at
    ? new Date(cardRow.expires_at).toLocaleDateString("es")
    : "Sin vencimiento";
  const balanceLabel = isGift ? "Saldo" : usesPoints ? "Puntos" : usesVisits ? "Accesos" : "Sellos";
  const primary = isGift
    ? { id: "primary", header: "SALDO", body: `🎁 Bs ${balance}` }
    : isMembership
    ? { id: "primary", header: "MEMBRESÍA", body: inactive ? "INACTIVA" : "ACTIVA" }
    : { id: "primary", header: balanceLabel.toUpperCase(), body: `${balance} de ${goal}` };
  const secondary = isMembership
    ? { id: "secondary", header: "VENCIMIENTO", body: expiration }
    : isGift
    ? { id: "secondary", header: "ESTADO", body: inactive ? "INACTIVA" : "ACTIVA" }
    : {
      id: "secondary",
      header: usesPoints ? "RECOMPENSA" : "PROGRESO",
      body: balance >= goal ? "COMPLETA" : `Faltan ${goal - balance}`,
    };
  return { balance, goal, balanceLabel, primary, secondary, isGift, isMembership, inactive };
}

function googleTemplateInfo() {
  const field = (id: string) => ({
    firstValue: { fields: [{ fieldPath: `object.textModulesData['${id}']` }] },
  });
  return {
    cardTemplateOverride: {
      cardRowTemplateInfos: [{
        twoItems: { startItem: field("primary"), endItem: field("secondary") },
      }],
    },
    listTemplateOverride: {
      firstRowOption: {
        fieldOption: { fields: [{ fieldPath: "object.textModulesData['primary']" }] },
      },
      secondRowOption: { fields: [{ fieldPath: "object.textModulesData['secondary']" }] },
    },
  };
}

function googleCredentials(): GoogleCredentials | null {
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw || !googleIssuerId) return null;
  try {
    const credentials = JSON.parse(raw) as GoogleCredentials;
    return credentials.client_email && credentials.private_key ? credentials : null;
  } catch {
    return null;
  }
}

function googleEnrollmentUrl(customerId: string, cardId?: string | null) {
  if (!googleCredentials()) return null;
  const result = new URL(`${functionBaseUrl}/api/wallet/google/${encodeURIComponent(customerId)}`);
  if (cardId) result.searchParams.set("card", cardId);
  result.searchParams.set("v", String(Date.now()));
  return result.toString();
}

async function syncGooglePassDesign(
  customerRow: Customer,
  cardRow: LoyaltyCard | null,
  updateObject = true,
) {
  if (!cardRow || !googleIssuerId) return;
  const token = await googleAccessToken();
  if (!token) return;
  const businessRow = await business(customerRow.business_id);
  const classId = `${googleIssuerId}.${googleClassSuffix}_${safeId(cardRow.id)}`;
  const logoUrl = `${functionBaseUrl}/assets/google/logo/${safeId(customerRow.business_id)}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`;
  const result = await fetch(
    `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyClass/${encodeURIComponent(classId)}`,
    {
      method: "PATCH",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({
        issuerName: businessRow.name,
        programName: cardRow.name,
        hexBackgroundColor: cardRow.color_hex || businessRow.color_hex,
        classTemplateInfo: googleTemplateInfo(),
        programLogo: {
          sourceUri: { uri: logoUrl },
          contentDescription: {
            defaultValue: { language: "es", value: `Logo de ${businessRow.name}` },
          },
        },
      }),
      signal: AbortSignal.timeout(7000),
    },
  );
  if (!result.ok && result.status !== 404) {
    throw new Error(`Google Wallet class update ${result.status}`);
  }
  if (updateObject) await updateGoogleCard(customerRow, cardRow, null);
}

async function syncGoogleBusinessDesign(businessId: string, onlyCardId?: string) {
  if (!googleIssuerId) return;
  let enrollmentQuery = admin
    .from("customer_card_enrollments")
    .select("customer_id,card_id")
    .eq("business_id", businessId);
  if (onlyCardId) enrollmentQuery = enrollmentQuery.eq("card_id", onlyCardId);
  const { data: enrollments, error: enrollmentError } = await enrollmentQuery;
  if (enrollmentError) throw enrollmentError;
  const pairs = [...new Map((enrollments || []).map((row) => [
    `${row.customer_id}:${row.card_id}`,
    { customerId: String(row.customer_id), cardId: String(row.card_id) },
  ])).values()];
  if (!pairs.length) return;
  const customerIds = [...new Set(pairs.map((pair) => pair.customerId))];
  const cardIds = [...new Set(pairs.map((pair) => pair.cardId))];
  const [{ data: customers, error: customersError }, { data: cards, error: cardsError }] = await Promise.all([
    admin.from("customers").select("*").eq("business_id", businessId).in("id", customerIds),
    admin.from("loyalty_cards").select("*").eq("business_id", businessId).in("id", cardIds),
  ]);
  if (customersError) throw customersError;
  if (cardsError) throw cardsError;
  const customerById = new Map((customers || []).map((row) => [String(row.id), row as Customer]));
  const cardById = new Map((cards || []).map((row) => [String(row.id), row as LoyaltyCard]));
  const cardCustomers = new Map<string, Customer>();
  for (const pair of pairs) {
    const customerRow = customerById.get(pair.customerId);
    if (customerRow && !cardCustomers.has(pair.cardId)) cardCustomers.set(pair.cardId, customerRow);
  }
  const classResults = await Promise.allSettled([...cardCustomers].map(async ([cardId, customerRow]) => {
    const cardRow = cardById.get(cardId);
    if (cardRow) await syncGooglePassDesign(customerRow, cardRow, false);
  }));
  classResults.forEach((result) => {
    if (result.status === "rejected") console.error("Google Wallet class design update failed", result.reason);
  });
  const objectResults = await Promise.allSettled(pairs.map(async ({ customerId, cardId }) => {
    const customerRow = customerById.get(customerId);
    const cardRow = cardById.get(cardId);
    if (customerRow && cardRow) await updateGoogleCard(customerRow, cardRow, null);
  }));
  objectResults.forEach((result) => {
    if (result.status === "rejected") console.error("Google Wallet object design update failed", result.reason);
  });
}

async function googleSaveUrl(
  customerRow: Customer,
  cardRow: LoyaltyCard | null = null,
) {
  const credentials = googleCredentials();
  if (!credentials) return null;
  const businessRow = await business(customerRow.business_id);
  const cardSuffix = cardRow ? `_${safeId(cardRow.id)}` : "";
  const classId = `${googleIssuerId}.${googleClassSuffix}${cardSuffix}`;
  const objectId = `${googleIssuerId}.${safeId(customerRow.id)}${cardSuffix}`;
  const cardValues = googleCardValues(customerRow, cardRow);
  const logoUrl = `${functionBaseUrl}/assets/google/logo/${safeId(customerRow.business_id)}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`;
  const heroUrl = cardRow && (cardRow.background_image_path ||
      (!cardValues.isGift && !cardValues.isMembership))
      ? `${functionBaseUrl}/assets/google/hero/${safeId(customerRow.id)}/${safeId(cardRow.id)}.png?v=${encodeURIComponent(`${cardValues.balance}-${cardRow.updated_at || "1"}-wallet-stamps-illustrated-v4`)}`
    : null;
  const now = Math.floor(Date.now() / 1000);
  const referralUrl = publicClubForBusiness(
    customerRow.business_id,
    String(businessRow.public_slug || ""),
  );
  referralUrl.searchParams.set("ref", customerRow.referral_code);
  referralUrl.searchParams.set("customer", customerRow.id);
  if (cardRow) referralUrl.searchParams.set("card", cardRow.id);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: credentials.client_email,
    aud: "google",
    origins: [
      new URL(publicClubUrl).origin,
      publicClubForBusiness(customerRow.business_id, String(businessRow.public_slug || "")).origin,
      new URL(googleLogoUrl).origin,
    ],
    typ: "savetowallet",
    iat: now,
    payload: {
      loyaltyClasses: [{
        id: classId,
        issuerName: businessRow.name,
        programName: cardRow?.name || `Club ${businessRow.name}`,
        reviewStatus: "UNDER_REVIEW",
        hexBackgroundColor: cardRow?.color_hex || businessRow.color_hex,
        countryCode: "BO",
        accountNameLabel: "CLIENTE",
        classTemplateInfo: googleTemplateInfo(),
        programLogo: {
          sourceUri: { uri: logoUrl },
          contentDescription: {
            defaultValue: { language: "es", value: `Logo de ${businessRow.name}` },
          },
        },
      }],
      loyaltyObjects: [{
        id: objectId,
        classId,
        state: cardValues.inactive ? "INACTIVE" : "ACTIVE",
        ...(googleMerchantLocations(businessRow).length
          ? { merchantLocations: googleMerchantLocations(businessRow) }
          : {}),
        accountName: customerRow.name,
        loyaltyPoints: {
          label: cardValues.balanceLabel,
          balance: { int: cardValues.balance },
        },
        ...(cardValues.inactive
          ? {}
          : {
              barcode: {
                type: "QR_CODE",
                value: customerQrPayload(customerRow.id, cardRow?.id, await qrTokenForCard(customerRow, cardRow)),
                alternateText: customerRow.referral_code,
              },
            }),
        ...(heroUrl
          ? {
              heroImage: {
                sourceUri: { uri: heroUrl },
                contentDescription: {
                  defaultValue: { language: "es", value: cardRow?.name || businessRow.name },
                },
              },
            }
          : {}),
        textModulesData: [
          cardValues.primary,
          cardValues.secondary,
          ...(cardRow?.welcome_message?.trim()
            ? [{
                id: "welcome",
                header: "Bienvenida",
                body: cardRow.welcome_message
                  .trim()
                  .replaceAll("{nombre}", customerRow.name),
              }]
            : []),
          ...(cardRow?.expiration_notice?.trim()
            ? [{
                id: "expiration-notice",
                header: "Aviso",
                body: cardRow.expiration_notice.trim(),
              }]
            : []),
          ...(!cardValues.isGift && !cardValues.isMembership && customerRow.tier
            ? [{ id: "tier", header: "Nivel", body: customerRow.tier }]
            : []),
        ],
        ...(customerRow.wallet_campaign_url
          ? {
              linksModuleData: {
                uris: [{
                  id: "campaign-link",
                  uri: customerRow.wallet_campaign_url,
                  description: "Ver promoción",
                }],
              },
            }
          : {}),
      }],
    },
  }));
  const unsigned = `${header}.${claims}`;
  const der = Buffer.from(
    credentials.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, ""),
    "base64",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  return `https://pay.google.com/gp/v/save/${unsigned}.${base64Url(signature)}`;
}

let googleAccessTokenCache: { token: string; expiresAt: number } | null = null;

async function googleAccessToken() {
  const credentials = googleCredentials();
  if (!credentials) return null;
  if (googleAccessTokenCache && googleAccessTokenCache.expiresAt > Date.now() + 60_000) {
    return googleAccessTokenCache.token;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/wallet_object.issuer",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const der = Buffer.from(
    credentials.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, ""),
    "base64",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    signal: AbortSignal.timeout(7000),
  });
  if (!tokenResponse.ok) throw new Error(`Google OAuth ${tokenResponse.status}`);
  const tokenBody = await tokenResponse.json();
  const token = String(tokenBody.access_token || "");
  if (!token) throw new Error("Google OAuth sin access_token");
  googleAccessTokenCache = {
    token,
    expiresAt: Date.now() + Number(tokenBody.expires_in || 3600) * 1000,
  };
  return token;
}

async function updateGoogleCampaign(
  businessId: string,
  customerIds: string[],
  notificationTitle: string,
  message: string,
  campaignUrl: string | null,
) {
  if (!customerIds.length || !googleIssuerId) return;
  const token = await googleAccessToken();
  if (!token) return;
  const { data: enrollments, error } = await admin
    .from("customer_card_enrollments")
    .select("customer_id,card_id")
    .eq("business_id", businessId)
    .in("customer_id", customerIds);
  if (error) throw error;
  const objectIds = new Set<string>();
  for (const customerId of customerIds) {
    // Keep the legacy object in the update set for customers who installed
    // their pass before Fideli started creating one Google object per card.
    objectIds.add(`${googleIssuerId}.${safeId(customerId)}`);
  }
  for (const enrollment of enrollments || []) {
    if (enrollment.customer_id && enrollment.card_id) {
      objectIds.add(`${googleIssuerId}.${safeId(String(enrollment.customer_id))}_${safeId(String(enrollment.card_id))}`);
    }
  }
  const results = await Promise.allSettled([...objectIds].map(async (objectId) => {
    const encodedId = encodeURIComponent(objectId);
    const patchResponse = await fetch(
        `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${encodedId}`,
        {
          method: "PATCH",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            linksModuleData: {
              uris: campaignUrl
                ? [{ id: "campaign-link", uri: campaignUrl, description: "Ver promoción" }]
                : [],
            },
          }),
          signal: AbortSignal.timeout(7000),
        },
    );
    if (!patchResponse.ok && patchResponse.status !== 404) {
      throw new Error(`Google Wallet patch ${patchResponse.status}`);
    }
    if (patchResponse.status === 404) return;
    const notifyResponse = await fetch(
      `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${encodedId}/addMessage`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            id: `campaign-${Date.now()}`,
            header: notificationTitle,
            body: message,
            messageType: "TEXT_AND_NOTIFY",
          },
        }),
        signal: AbortSignal.timeout(7000),
      },
    );
    if (!notifyResponse.ok && notifyResponse.status !== 404) {
      throw new Error(`Google Wallet notification ${notifyResponse.status}`);
    }
  }));
  results.forEach((result) => {
    if (result.status === "rejected") console.error("Google Wallet campaign object update failed", result.reason);
  });
}

async function updateGoogleCard(
  customerRow: Customer,
  cardRow: LoyaltyCard,
  notificationMessage: string | null,
) {
  if (!googleIssuerId) return;
  const token = await googleAccessToken();
  if (!token) return;
  const cardSuffix = `_${safeId(cardRow.id)}`;
  const currentObjectId = `${googleIssuerId}.${safeId(customerRow.id)}${cardSuffix}`;
  // Antes de que cada tarjeta tuviera su propio objeto, Google Wallet guardaba
  // la tarjeta principal usando solo el id del cliente. Mantener ese pase
  // actualizado evita que los clientes que ya lo instalaron vean un saldo viejo.
  const defaultCard = await loyaltyCard(customerRow.business_id);
  const objectIds = [currentObjectId];
  if (defaultCard?.id === cardRow.id) {
    objectIds.push(`${googleIssuerId}.${safeId(customerRow.id)}`);
  }
  const cardValues = googleCardValues(customerRow, cardRow);
  const businessRow = await business(customerRow.business_id);
  const heroUrl = `${functionBaseUrl}/assets/google/hero/${safeId(customerRow.id)}/${safeId(cardRow.id)}.png?v=${encodeURIComponent(`${cardValues.balance}-${cardRow.updated_at || Date.now()}-wallet-stamps-illustrated-v4`)}`;
  const patchBody = {
    state: cardValues.inactive ? "INACTIVE" : "ACTIVE",
    merchantLocations: googleMerchantLocations(businessRow),
    barcode: cardValues.inactive
      ? null
      : {
        type: "QR_CODE",
        value: customerQrPayload(customerRow.id, cardRow.id, await qrTokenForCard(customerRow, cardRow)),
        alternateText: customerRow.referral_code,
      },
    loyaltyPoints: {
      label: cardValues.balanceLabel,
      balance: { int: cardValues.balance },
    },
    heroImage: {
      sourceUri: { uri: heroUrl },
      contentDescription: {
        defaultValue: { language: "es", value: cardRow.name },
      },
    },
    textModulesData: [
      cardValues.primary,
      cardValues.secondary,
      ...(cardRow.welcome_message?.trim()
        ? [{
          id: "welcome",
          header: "Bienvenida",
          body: cardRow.welcome_message
            .trim()
            .replaceAll("{nombre}", customerRow.name),
        }]
        : []),
      ...(cardRow.expiration_notice?.trim()
        ? [{
          id: "expiration-notice",
          header: "Aviso",
          body: cardRow.expiration_notice.trim(),
        }]
        : []),
    ],
  };
  const patchResults = await Promise.all(objectIds.map(async (candidateId) => {
    const patchResponse = await fetch(
      `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${encodeURIComponent(candidateId)}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(patchBody),
        signal: AbortSignal.timeout(7000),
      },
    );
    if (patchResponse.ok) return candidateId;
    if (patchResponse.status !== 404) throw new Error(`Google Wallet progress update ${patchResponse.status}`);
    return null;
  }));
  const updatedObjectIds = patchResults.filter((value): value is string => Boolean(value));
  if (!updatedObjectIds.length) {
    throw new Error("Google Wallet no encontró el pase instalado para actualizar");
  }
  if (notificationMessage) {
    await Promise.all(updatedObjectIds.map(async (updatedObjectId) => {
      const notifyResponse = await fetch(
        `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${encodeURIComponent(updatedObjectId)}/addMessage`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              id: `progress-${Date.now()}`,
              header: cardRow.name,
              body: notificationMessage,
              messageType: "TEXT_AND_NOTIFY",
            },
          }),
          signal: AbortSignal.timeout(7000),
        },
      );
      if (!notifyResponse.ok && notifyResponse.status !== 404) {
        throw new Error(`Google Wallet progress notification ${notifyResponse.status}`);
      }
    }));
  }
}

async function expireGooglePasses(customerIds: string[]) {
  if (!customerIds.length || !googleIssuerId) return;
  const token = await googleAccessToken();
  if (!token) return;
  await Promise.allSettled(customerIds.map(async (customerId) => {
    const objectId = encodeURIComponent(`${googleIssuerId}.${customerId}`);
    const result = await fetch(
      `https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${objectId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ state: "EXPIRED" }),
        signal: AbortSignal.timeout(7000),
      },
    );
    if (!result.ok && result.status !== 404) {
      throw new Error(`Google Wallet expiration ${result.status}`);
    }
  }));
}

async function apnsJwt() {
  const pem = Deno.env.get("APPLE_APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const keyId = Deno.env.get("APPLE_APNS_KEY_ID");
  if (!pem || !keyId) return null;
  const der = Buffer.from(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, ""), "base64");
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64Url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const unsigned = `${header}.${claims}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  return `${unsigned}.${base64Url(signature)}`;
}

async function cleanupOrphanWalletDevices() {
  const [{ data: devices }, { data: registrations }] = await Promise.all([
    admin.from("wallet_devices").select("device_library_identifier"),
    admin.from("wallet_registrations").select("device_library_identifier"),
  ]);
  const used = new Set((registrations || []).map((item) => item.device_library_identifier as string));
  const orphanIds = (devices || [])
    .map((item) => item.device_library_identifier as string)
    .filter((id) => !used.has(id));
  if (orphanIds.length) {
    await admin.from("wallet_devices").delete().in("device_library_identifier", orphanIds);
  }
}

async function notifyPasses(serialNumbers: string[]) {
  // Wallet pass pushes authenticate with the same Pass Type certificate used
  // to sign the pass, not with the app's generic APNs token key.
  const cert = Deno.env.get("APPLE_SIGNER_CERT_PEM")?.replace(/\\n/g, "\n");
  const key = Deno.env.get("APPLE_SIGNER_KEY_PEM")?.replace(/\\n/g, "\n");
  if (!cert || !key) return { delivered: 0, registered: 0, configured: false };
  if (!serialNumbers.length) return { delivered: 0, registered: 0, configured: true };
  const { data: registrations } = await admin
    .from("wallet_registrations")
    .select("device_library_identifier,wallet_devices(push_token)")
    .in("serial_number", [...new Set(serialNumbers)]);
  if (!registrations?.length) return { delivered: 0, registered: 0, configured: true };
  const devices = new Map<string, string>();
  for (const registration of registrations) {
    const device = registration.wallet_devices as unknown as { push_token: string };
    if (device?.push_token) {
      devices.set(registration.device_library_identifier as string, device.push_token);
    }
  }
  const client = Deno.createHttpClient({ cert, key, http1: false, http2: true });
  try {
    const deliveries = await Promise.all([...devices.entries()].map(async ([deviceId, pushToken]) => {
      try {
        const result = await fetch(`https://api.push.apple.com/3/device/${pushToken}`, {
        method: "POST",
        headers: {
          "apns-topic": passTypeId,
          "apns-push-type": "background",
          "apns-priority": "5",
          // An old Wallet refresh is no longer useful hours later. Ask APNs to
          // deliver it promptly while Wallet can fetch the current revision.
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 60),
          "apns-collapse-id": "fideli-wallet-refresh",
        },
        body: "{}",
        signal: AbortSignal.timeout(5000),
        client,
        });
        if (result.ok) return 1;
        const failure = await result.text();
        console.error("Apple Wallet push failed", result.status, failure);
        if (result.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(failure)) {
          await admin.from("wallet_devices").delete().eq("device_library_identifier", deviceId);
        }
      } catch (error) {
        console.error("Apple Wallet push failed", error);
      }
      return 0;
    }));
    return {
      delivered: deliveries.reduce<number>((sum, value) => sum + value, 0),
      registered: devices.size,
      configured: true,
    };
  } finally {
    client.close();
  }
}

function notifyPassesInBackground(serialNumbers: string[]) {
  const uniqueSerials = [...new Set(serialNumbers)];
  if (!uniqueSerials.length) return;
  EdgeRuntime.waitUntil(
    notifyPasses(uniqueSerials).catch((error) => {
      console.error("Background Wallet notification failed", error);
    }),
  );
}

async function notifyPass(serial: string) {
  return await notifyPasses([serial]);
}

async function deletePassRecords(serialNumbers: string[]) {
  if (!serialNumbers.length) return;
  const { data: registrations } = await admin
    .from("wallet_registrations")
    .select("device_library_identifier")
    .in("serial_number", serialNumbers);
  const deviceIds = [...new Set((registrations || []).map((item) => item.device_library_identifier as string))];
  const { error } = await admin.from("wallet_passes").delete().in("serial_number", serialNumbers);
  if (error) throw error;
  EdgeRuntime.waitUntil(Promise.all(deviceIds.map(async (deviceId) => {
    const { count } = await admin
      .from("wallet_registrations")
      .select("*", { count: "exact", head: true })
      .eq("device_library_identifier", deviceId);
    if (!count) await admin.from("wallet_devices").delete().eq("device_library_identifier", deviceId);
  })).then(() => undefined));
}

async function removeArtworkFolder(folder: string | null | undefined, names: string[]) {
  if (!folder) return;
  await admin.storage.from("business-assets").remove(names.map((name) => `${folder}/${name}`));
}

async function cleanupVersionedArtwork(
  businessId: string,
  category: "wallet" | "logo",
  currentFolder: string | null | undefined,
  names: string[],
) {
  const prefix = `${businessId}/${category}`;
  const { data: versions } = await admin.storage.from("business-assets").list(prefix, { limit: 1000 });
  for (const version of versions || []) {
    const folder = `${prefix}/${version.name}`;
    if (folder !== currentFolder) await removeArtworkFolder(folder, names);
  }
}

type ExpirationReminder = {
  key: string;
  offsetMs: number;
  label: string;
};

function expirationReminders(cardRow: LoyaltyCard): ExpirationReminder[] {
  const hour = 60 * 60 * 1000;
  const day = 24 * hour;
  return [
    { key: "7d", offsetMs: 7 * day, label: "1 semana" },
    { key: "4d", offsetMs: 4 * day, label: "4 días" },
    { key: "1d", offsetMs: day, label: "1 día" },
    { key: "1h", offsetMs: hour, label: "1 hora" },
  ];
}

function expirationMessage(
  _cardRow: LoyaltyCard,
  reminder: ExpirationReminder | null,
) {
  if (!reminder) return "La tarjeta ya venció.";
  return `La tarjeta se vence en ${reminder.label}.`;
}

async function processExpirationNotifications() {
  const now = Date.now();
  const windowMs = 20 * 60 * 1000;
  const maxFuture = new Date(now + 7 * 24 * 60 * 60 * 1000 + windowMs).toISOString();
  const recentPast = new Date(now - 24 * 60 * 60 * 1000).toISOString();
  const { data: dueCards, error } = await admin
    .from("loyalty_cards")
    .select("*")
    .not("expires_at", "is", null)
    .gte("expires_at", recentPast)
    .lte("expires_at", maxFuture);
  if (error) throw error;

  let processed = 0;
  for (const rawCard of dueCards || []) {
    const cardRow = rawCard as LoyaltyCard;
    const expirationMs = new Date(cardRow.expires_at!).getTime();
    const remainingMs = expirationMs - now;
    const reminder = remainingMs <= 0
      ? null
      : expirationReminders(cardRow).find((item) =>
        remainingMs <= item.offsetMs && remainingMs > item.offsetMs - windowMs
      ) || undefined;
    if (remainingMs > 0 && !reminder) continue;
    const reminderKey = reminder?.key || "expired";

    const { error: reserveError } = await admin
      .from("card_expiration_notifications")
      .insert({
        business_id: cardRow.business_id,
        card_id: cardRow.id,
        reminder_key: reminderKey,
      });
    if (reserveError) {
      if (reserveError.code === "23505") continue;
      throw reserveError;
    }

    const message = expirationMessage(cardRow, reminder || null);
    const update = {
      expiration_notice: walletNotificationValue(message),
      expiration_notice_key: reminderKey,
      ...(reminderKey === "expired" ? { active: false } : {}),
      updated_at: new Date().toISOString(),
    };
    const { data: updatedCard, error: updateError } = await admin
      .from("loyalty_cards")
      .update(update)
      .eq("business_id", cardRow.business_id)
      .eq("id", cardRow.id)
      .select("*")
      .single();
    if (updateError) throw updateError;
    const currentCard = updatedCard as LoyaltyCard;

    const [{ data: customers }, { data: passes }] = await Promise.all([
      admin.from("customers").select("*")
        .eq("business_id", cardRow.business_id)
        .is("deleted_at", null),
      admin.from("wallet_passes").select("serial_number,customer_id")
        .eq("business_id", cardRow.business_id)
        .eq("card_id", cardRow.id),
    ]);
    const passCustomerIds = new Set(
      (passes || []).map((item) => String(item.customer_id || "")).filter(Boolean),
    );
    const enrolledCustomers = ((customers || []) as Customer[]).filter((customerRow) =>
      Boolean(customerRow.card_balances?.[cardRow.id]) || passCustomerIds.has(customerRow.id)
    );
    const customerIds = enrolledCustomers.map((customerRow) => customerRow.id);
    const serialNumbers = (passes || []).map((item) => String(item.serial_number));

    if (serialNumbers.length) {
      await admin.from("wallet_passes")
        .update({ update_tag: Date.now(), updated_at: new Date().toISOString() })
        .in("serial_number", serialNumbers);
      notifyPassesInBackground(serialNumbers);
    }
    const businessRow = await business(cardRow.business_id);
    await Promise.allSettled([
      broadcastPwaCardUpdate(cardRow.business_id, customerIds, "card_expiration"),
      sendWebPush(
        cardRow.business_id,
        customerIds,
        String(businessRow.name || currentCard.name),
        message,
      ),
      ...enrolledCustomers.map((customerRow) =>
        updateGoogleCard(customerRow, currentCard, message)
      ),
    ]);
    processed++;
  }
  return processed;
}

type PendingRewardClaim = {
  business_id: string;
  customer_id: string;
  reward_id: string;
  program_id: string;
  reward_name: string;
  earned_at: string;
  reminder_count: number;
  last_reminder_at?: string | null;
  claimed_at?: string | null;
};

async function syncRewardClaimsForCustomers(
  businessId: string,
  customers: Customer[],
  cards: LoyaltyCard[],
) {
  if (!customers.length || !cards.length) return 0;
  const { data: rewardRecords, error } = await admin
    .from("module_records")
    .select("payload")
    .eq("business_id", businessId)
    .eq("module_type", "reward");
  if (error) throw error;

  const cardById = new Map(cards.map((card) => [card.id, card]));
  let inserted = 0;
  for (const customerRow of customers) {
    const candidates = new Map<string, { programId: string; name: string }>();
    for (const row of rewardRecords || []) {
      const reward = row.payload as Record<string, unknown>;
      const rewardId = String(reward.id || "");
      const programId = String(reward.programId || "");
      const card = cardById.get(programId);
      const balance = customerRow.card_balances?.[programId];
      const pointsCost = Math.max(0, Number(reward.pointsCost) || 0);
      const stampsCost = Math.max(0, Number(reward.stampsCost) || 0);
      if (
        rewardId && reward.active !== false && card?.active && balance &&
        (pointsCost > 0 || stampsCost > 0) &&
        Number(balance.points || 0) >= pointsCost &&
        Number(balance.stamps || 0) >= stampsCost
      ) {
        candidates.set(rewardId, {
          programId,
          name: String(reward.name || "Premio"),
        });
      }
    }
    for (const card of cards) {
      if (!card.active) continue;
      const stamps = Number(customerRow.card_balances?.[card.id]?.stamps || 0);
      for (const milestone of card.reward_milestones || []) {
        const rewardId = String(milestone.id || "");
        const stamp = Math.max(1, Number(milestone.stamp) || 0);
        if (rewardId && stamps >= stamp) {
          candidates.set(rewardId, {
            programId: card.id,
            name: String(milestone.reward || "Premio de la tarjeta"),
          });
        }
      }
    }
    if (!candidates.size) continue;

    const rewardIds = [...candidates.keys()];
    const { data: redemptions, error: redemptionError } = await admin
      .from("customer_reward_redemptions")
      .select("reward_id")
      .eq("business_id", businessId)
      .eq("customer_id", customerRow.id)
      .in("reward_id", rewardIds);
    if (redemptionError) throw redemptionError;
    const redeemed = new Set((redemptions || []).map((row) => String(row.reward_id)));
    const now = new Date().toISOString();
    const rows = [...candidates.entries()].map(([rewardId, candidate]) => ({
      business_id: businessId,
      customer_id: customerRow.id,
      reward_id: rewardId,
      program_id: candidate.programId,
      reward_name: candidate.name,
      earned_at: now,
      ...(redeemed.has(rewardId) ? { claimed_at: now } : {}),
    }));
    const { error: claimError, count } = await admin
      .from("customer_reward_claims")
      .upsert(rows, {
        onConflict: "business_id,customer_id,reward_id",
        ignoreDuplicates: true,
        count: "exact",
      });
    if (claimError) throw claimError;
    inserted += count || 0;
    if (redeemed.size) {
      await admin.from("customer_reward_claims")
        .update({ claimed_at: now })
        .eq("business_id", businessId)
        .eq("customer_id", customerRow.id)
        .in("reward_id", [...redeemed])
        .is("claimed_at", null);
    }
  }
  return inserted;
}

async function processPendingRewardReminders() {
  const [{ data: cards, error: cardError }, { data: customers, error: customerError }] =
    await Promise.all([
      admin.from("loyalty_cards").select("*").eq("active", true),
      admin.from("customers").select("*").is("deleted_at", null),
    ]);
  if (cardError) throw cardError;
  if (customerError) throw customerError;

  const cardsByBusiness = new Map<string, LoyaltyCard[]>();
  for (const raw of cards || []) {
    const card = raw as LoyaltyCard;
    cardsByBusiness.set(card.business_id, [
      ...(cardsByBusiness.get(card.business_id) || []),
      card,
    ]);
  }
  const customersByBusiness = new Map<string, Customer[]>();
  for (const raw of customers || []) {
    const customerRow = raw as Customer;
    customersByBusiness.set(customerRow.business_id, [
      ...(customersByBusiness.get(customerRow.business_id) || []),
      customerRow,
    ]);
  }
  for (const [businessId, businessCustomers] of customersByBusiness) {
    await syncRewardClaimsForCustomers(
      businessId,
      businessCustomers,
      cardsByBusiness.get(businessId) || [],
    );
  }

  const cutoff = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString();
  const { data: dueClaims, error: claimError } = await admin
    .from("customer_reward_claims")
    .select("*")
    .is("claimed_at", null)
    .lte("earned_at", cutoff)
    .or(`last_reminder_at.is.null,last_reminder_at.lte.${new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()}`)
    .order("earned_at", { ascending: true });
  if (claimError) throw claimError;
  const claims = (dueClaims || []) as PendingRewardClaim[];
  if (!claims.length) return 0;

  const copy = [
    (count: number) => count === 1
      ? "Tienes 1 regalo pendiente. ¡Ven a canjearlo!"
      : `Tienes ${count} regalos pendientes. ¡Ven a canjearlos!`,
    (count: number) => count === 1
      ? "Tienes un premio pendiente. ¡Te esperamos en el local!"
      : `Tienes ${count} premios pendientes. ¡Te esperamos en el local!`,
    (count: number) => count === 1
      ? "¡No te olvides! Tienes 1 regalo por reclamar."
      : `¡No te olvides! Tienes ${count} regalos por reclamar.`,
    (count: number) => count === 1
      ? "Tu premio te está esperando. ¡Ven a canjearlo!"
      : `Tus ${count} premios te están esperando. ¡Ven a canjearlos!`,
  ];
  const customerIdsByBusiness = new Map<string, Set<string>>();
  for (const claim of claims) {
    customerIdsByBusiness.set(claim.business_id, new Set([
      ...(customerIdsByBusiness.get(claim.business_id) || []),
      claim.customer_id,
    ]));
  }

  let sent = 0;
  for (const [businessId, customerIdSet] of customerIdsByBusiness) {
    const ids = [...customerIdSet];
    const [{ data: businessCustomers }, businessRow] = await Promise.all([
      admin.from("customers").select("*").eq("business_id", businessId).in("id", ids),
      business(businessId),
    ]);
    const customerById = new Map(
      ((businessCustomers || []) as Customer[]).map((row) => [row.id, row]),
    );
    // Include every pending reward in the total, even if it is not due yet.
    const { data: pendingClaims, error: pendingError } = await admin
      .from("customer_reward_claims")
      .select("*")
      .eq("business_id", businessId)
      .in("customer_id", ids)
      .is("claimed_at", null);
    if (pendingError) throw pendingError;
    const relevantClaims = (pendingClaims || []) as PendingRewardClaim[];
    for (const customerId of ids) {
      const customerRow = customerById.get(customerId);
      const customerClaims = relevantClaims.filter((claim) => claim.customer_id === customerId);
      if (!customerRow || !customerClaims.length) continue;
      const nextCount = Math.max(...customerClaims.map((claim) => claim.reminder_count || 0)) + 1;
      const message = copy[(nextCount - 1) % copy.length](customerClaims.length);
      const now = new Date().toISOString();
      await admin.from("customer_reward_claims")
        .update({ reminder_count: nextCount, last_reminder_at: now })
        .eq("business_id", businessId)
        .eq("customer_id", customerId)
        .in("reward_id", customerClaims.map((claim) => claim.reward_id))
        .is("claimed_at", null);

      await sendWebPush(
        businessId,
        [customerId],
        String(businessRow.name || "Fideli"),
        message,
        null,
        customerClaims[0].program_id,
      );
      const programIds = [...new Set(customerClaims.map((claim) => claim.program_id))];
      await Promise.allSettled(programIds.map(async (programId) => {
        const card = (cardsByBusiness.get(businessId) || []).find((item) => item.id === programId);
        if (card) await updateGoogleCard(customerRow, card, message);
      }));
      await admin.from("customers").update({
        wallet_message: walletNotificationValue(message),
        updated_at: now,
      }).eq("business_id", businessId).eq("id", customerId);
      const { data: passes } = await admin.from("wallet_passes")
        .select("serial_number")
        .eq("business_id", businessId)
        .eq("customer_id", customerId);
      const serials = (passes || []).map((row) => String(row.serial_number));
      if (serials.length) {
        await admin.from("wallet_passes").update({
          update_tag: Date.now(),
          updated_at: now,
        }).eq("business_id", businessId).in("serial_number", serials);
        notifyPassesInBackground(serials);
      }
      sent += customerClaims.length;
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const url = new URL(req.url);
  const path = url.pathname
    .replace(/^\/functions\/v1\/wallet/, "")
    .replace(/^\/wallet/, "");

  try {
    if (req.method === "POST" && path === "/api/cron/expirations") {
      const authorization = req.headers.get("authorization") || "";
      const allowedKeys = new Set([
        publicCronKey,
        Deno.env.get("SUPABASE_ANON_KEY") || "",
        Deno.env.get("SB_PUBLISHABLE_KEY") || "",
      ]);
      const suppliedKey = authorization.replace(/^Bearer\s+/i, "");
      if (!suppliedKey || !allowedKeys.has(suppliedKey)) {
        return response({ message: "No autorizado" }, 401);
      }
      const processed = await processExpirationNotifications();
      return response({ ok: true, processed });
    }

    if (req.method === "POST" && path === "/api/cron/reward-claims") {
      const authorization = req.headers.get("authorization") || "";
      const allowedKeys = new Set([
        publicCronKey,
        Deno.env.get("SUPABASE_ANON_KEY") || "",
        Deno.env.get("SB_PUBLISHABLE_KEY") || "",
      ]);
      const suppliedKey = authorization.replace(/^Bearer\s+/i, "");
      if (!suppliedKey || !allowedKeys.has(suppliedKey)) {
        return response({ message: "No autorizado" }, 401);
      }
      const remindersSent = await processPendingRewardReminders();
      return response({ ok: true, remindersSent });
    }

    if (req.method === "GET" && path === "/assets/icon.png") {
      return new Response(icon, {
        status: 200,
        headers: { ...cors, "content-type": "image/png", "cache-control": "public, max-age=86400" },
      });
    }

    const googleLogoAsset = path.match(/^\/assets\/google\/logo\/([^/]+)\.png$/);
    if (req.method === "GET" && googleLogoAsset) {
      const businessRow = await business(safeId(googleLogoAsset[1]));
      const artwork = await walletArtwork(
        String(businessRow.wallet_icon_path || ""),
        null,
        String(businessRow.wallet_logo_path || ""),
      );
      const png = artwork["icon@3x.png"] || artwork["icon@2x.png"] ||
        artwork["icon.png"] || icon2x;
      return new Response(new Uint8Array(png), {
        status: 200,
        headers: {
          ...cors,
          "content-type": "image/png",
          "cache-control": "public, max-age=3600",
        },
      });
    }

    const pwaLogoAsset = path.match(/^\/assets\/pwa\/logo\/([^/]+)\.png$/);
    if (req.method === "GET" && pwaLogoAsset) {
      const businessRow = await business(safeId(pwaLogoAsset[1]));
      const artwork = await walletArtwork(
        String(businessRow.wallet_icon_path || ""),
        null,
        String(businessRow.wallet_logo_path || ""),
      );
      const png = artwork["logo@3x.png"] || artwork["logo@2x.png"] ||
        artwork["logo.png"] || artwork["icon@2x.png"] || icon2x;
      return new Response(new Uint8Array(png), {
        status: 200,
        headers: { ...cors, "content-type": "image/png", "cache-control": "public, max-age=3600" },
      });
    }

    const pwaBackgroundAsset = path.match(
      /^\/assets\/pwa\/background\/([0-9a-f-]{36})\/([^/]+)\.png$/i,
    );
    if (req.method === "GET" && pwaBackgroundAsset) {
      const businessRow = await business(pwaBackgroundAsset[1]);
      const cardRow = await loyaltyCard(pwaBackgroundAsset[1], safeId(pwaBackgroundAsset[2]));
      if (!cardRow?.background_image_path) return response({ message: "Imagen no encontrada" }, 404);
      const artwork = await walletArtwork(
        String(businessRow.wallet_icon_path || ""),
        cardRow.background_image_path,
        String(businessRow.wallet_logo_path || ""),
      );
      const source = artwork["source-background.png"];
      if (!source) return response({ message: "Imagen no encontrada" }, 404);
      const usesFullBackground = cardRow.wallet_layout !== "classic" && (
        cardRow.card_kind === "Tarjeta de regalo" ||
        cardRow.program_type === "points" ||
        cardRow.program_type === "visits" ||
        cardRow.program_type === "membership"
      );
      if (usesFullBackground) await ensureImageMagick();
      // Apple Wallet recibe exactamente este recorte 360x440 para su fondo.
      // Servir el mismo recorte evita que la PWA muestre otra zona de la foto.
      const png = usesFullBackground ? renderCover(source, 360, 440) : source;
      return new Response(new Uint8Array(png), {
        status: 200,
        headers: { ...cors, "content-type": "image/png", "cache-control": "public, max-age=3600" },
      });
    }

    const pwaQrAsset = path.match(
      /^\/assets\/pwa\/qr\/([0-9a-f-]{36})\/([^/.]+)\.svg$/i,
    );
    if (req.method === "GET" && pwaQrAsset) {
      const businessId = pwaQrAsset[1];
      const customerId = safeId(decodeURIComponent(pwaQrAsset[2]));
      const cardId = safeId(String(url.searchParams.get("card") || ""));
      const token = String(url.searchParams.get("token") || "");
      const { data: customerRow } = await admin.from("customers")
        .select("id,business_id,referral_code,pwa_access_token,deleted_at")
        .eq("business_id", businessId)
        .eq("id", customerId)
        .maybeSingle();
      if (!customerRow || customerRow.deleted_at || !token || token !== customerRow.pwa_access_token) {
        return response({ message: "Código no encontrado" }, 404);
      }
      const cardRow = cardId ? await loyaltyCard(businessId, cardId) : await loyaltyCard(businessId);
      const cardExpired = Boolean(
        cardRow?.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now(),
      );
      if (!cardRow || cardRow.active === false || cardExpired) {
        return response({ message: "Esta tarjeta ya venció" }, 410);
      }
      const allowsPersonalSharing =
        (cardRow.program_type === "points" || cardRow.program_type === "stamps") &&
        cardRow.card_kind !== "Tarjeta de regalo";
      if (!allowsPersonalSharing) {
        return response({ message: "El QR personal de esta tarjeta está protegido" }, 403);
      }
      const svg = await QRCode.toString(customerQrPayload(customerId, cardId, token), {
        type: "svg",
        width: 384,
        margin: 4,
        errorCorrectionLevel: "M",
        color: { dark: "#000000", light: "#ffffff" },
      });
      return new Response(svg, {
        headers: {
          ...cors,
          "content-type": "image/svg+xml; charset=utf-8",
          "cache-control": "private, no-store",
          "x-content-type-options": "nosniff",
        },
      });
    }

    const pwaManifest = path.match(/^\/api\/public\/pwa\/manifest\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && pwaManifest) {
      const businessRow = await business(pwaManifest[1]);
      const name = String(businessRow.name || "Fideli").slice(0, 80);
      const manifestBase = publicClubForBusiness(
        pwaManifest[1],
        String(businessRow.public_slug || ""),
      );
      const manifestOrigin = manifestBase.origin;
      const requestedStart = String(url.searchParams.get("start") || manifestBase.toString());
      let startUrl = manifestBase.toString();
      try {
        const candidate = new URL(requestedStart);
        const allowedHost = candidate.hostname === "fideli.site" ||
          candidate.hostname === "www.fideli.site" || candidate.hostname.endsWith(".fideli.site");
        if (candidate.protocol === "https:" && allowedHost) startUrl = candidate.toString();
      } catch (_) {}
      const logoUrl = `${functionBaseUrl}/assets/google/logo/${pwaManifest[1]}.png`;
      return new Response(JSON.stringify({
        id: `${manifestOrigin}/pwa/${pwaManifest[1]}`,
        name,
        short_name: name,
        description: `Tarjeta digital de ${name}`,
        start_url: startUrl,
        scope: `${manifestOrigin}/`,
        display: "standalone",
        background_color: "#ffffff",
        theme_color: String(businessRow.color_hex || "#ffffff"),
        icons: [
          { src: logoUrl, sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: logoUrl, sizes: "512x512", type: "image/png", purpose: "any maskable" },
        ],
      }), {
        headers: { ...cors, "content-type": "application/manifest+json", "cache-control": "no-store" },
      });
    }

    const googleHeroAsset = path.match(/^\/assets\/google\/hero\/([^/]+)\/([^/]+)\.png$/);
    if (req.method === "GET" && googleHeroAsset) {
      const customerRow = await customer(safeId(googleHeroAsset[1]));
      if (!customerRow || customerRow.deleted_at) {
        return response({ message: "No encontrado" }, 404);
      }
      const cardRow = await loyaltyCard(
        customerRow.business_id,
        safeId(googleHeroAsset[2]),
      );
      if (!cardRow) return response({ message: "Tarjeta no encontrada" }, 404);
      const businessRow = await business(customerRow.business_id);
      const artwork = await walletArtwork(
        String(businessRow.wallet_icon_path || ""),
        cardRow.background_image_path,
        String(businessRow.wallet_logo_path || ""),
      );
      const background = artwork["source-background.png"];
      await ensureImageMagick();
      const values = googleCardValues(customerRow, cardRow);
      const isStampCard = cardRow.program_type !== "points" &&
        cardRow.program_type !== "visits" &&
        cardRow.program_type !== "membership" &&
        cardRow.card_kind !== "Tarjeta de regalo";
      const png = isStampCard
        ? renderStampStrip(
          cardRow.stamp_icon || "coffee",
          values.balance,
          values.goal,
          3,
          background,
        )
        : background
        ? renderCover(background, 1125, 369)
        : ImageMagick.read(
          new MagickColor(cardRow.color_hex || businessRow.color_hex || "#6750A4"),
          1125,
          369,
          (image) => image.write(MagickFormat.Png, (data) => Buffer.from(data)),
        );
      return new Response(png, {
        status: 200,
        headers: {
          ...cors,
          "content-type": "image/png",
          "cache-control": "public, max-age=300",
        },
      });
    }

    const stampAsset = path.match(/^\/assets\/stamps\/(coffee|pizza|haircut|star|heart|paw|check|gift|hamburger|latte|coffee_beans|ice_cream|hair_scissors|salon_chair|pet_collar|pet_bone|pet_bowl)\.png$/);
    if (req.method === "GET" && stampAsset) {
      await ensureImageMagick();
      const png = ImageMagick.read(MagickColors.Transparent, 96, 96, (image) => {
        drawStamp(stampAsset[1], 2, 2, 2, 1, image);
        return image.write(MagickFormat.Png, (data) => Buffer.from(data));
      });
      return new Response(png, {
        status: 200,
        headers: { ...cors, "content-type": "image/png", "cache-control": "public, max-age=86400" },
      });
    }

    if (req.method === "GET" && path === "/health") {
      return response({
        ok: true,
        mode: "real",
        apple: Boolean(passTypeId && teamId),
        appleAutomaticUpdates: Boolean(
          Deno.env.get("APPLE_SIGNER_CERT_PEM") && Deno.env.get("APPLE_SIGNER_KEY_PEM"),
        ),
        google: Boolean(googleCredentials()),
        database: true,
      });
    }

    const publicClubBySlugApi = path.match(
      /^\/api\/public\/clubs\/by-slug\/([a-z0-9]+(?:-[a-z0-9]+)*)$/i,
    );
    if (req.method === "GET" && publicClubBySlugApi) {
      const publicSlug = publicClubBySlugApi[1].toLowerCase();
      const { data: businessRow } = await admin
        .from("businesses")
        .select("id,name,color_hex,wallet_icon_path,wallet_logo_path,public_slug,locations,updated_at")
        .eq("public_slug", publicSlug)
        .maybeSingle();
      if (!businessRow) return response({ message: "Club no encontrado" }, 404);
      const { data: cards } = await admin
        .from("loyalty_cards")
        .select("id,name,card_kind,program_type,goal,expires_at,color_hex,background_image_path,stamp_icon,wallet_layout,active,updated_at")
        .eq("business_id", businessRow.id)
        .neq("card_kind", "Evento")
        .eq("active", true)
        .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`)
        .order("created_at", { ascending: true });
      return response({
        id: businessRow.id,
        name: businessRow.name,
        publicSlug: businessRow.public_slug,
        colorHex: businessRow.color_hex,
        locations: businessLocations(businessRow),
        logoUrl: `${functionBaseUrl}/assets/pwa/logo/${businessRow.id}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`,
        iconUrl: `${functionBaseUrl}/assets/google/logo/${businessRow.id}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`,
        cards: ((cards || []) as LoyaltyCard[]).map((card) => ({
          ...card,
          preview: publicCardPayload(businessRow, card as LoyaltyCard),
        })),
      });
    }

    const publicClubApi = path.match(/^\/api\/public\/clubs\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && publicClubApi) {
      const { data: businessRow } = await admin
        .from("businesses")
        .select("id,name,color_hex,wallet_icon_path,wallet_logo_path,public_slug,locations,updated_at")
        .eq("id", publicClubApi[1])
        .maybeSingle();
      if (!businessRow) return response({ message: "Club no encontrado" }, 404);
      const { data: cards } = await admin
        .from("loyalty_cards")
        .select("id,name,card_kind,program_type,goal,expires_at,color_hex,background_image_path,stamp_icon,wallet_layout,active,updated_at")
        .eq("business_id", businessRow.id)
        .neq("card_kind", "Evento")
        .eq("active", true)
        .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`)
        .order("created_at", { ascending: true });
      return response({
        id: businessRow.id,
        name: businessRow.name,
        publicSlug: businessRow.public_slug,
        colorHex: businessRow.color_hex,
        locations: businessLocations(businessRow),
        logoUrl: `${functionBaseUrl}/assets/pwa/logo/${businessRow.id}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`,
        iconUrl: `${functionBaseUrl}/assets/google/logo/${businessRow.id}.png?v=${encodeURIComponent(String(businessRow.updated_at || "1"))}`,
        cards: ((cards || []) as LoyaltyCard[]).map((card) => ({
          ...card,
          preview: publicCardPayload(businessRow, card as LoyaltyCard),
        })),
      });
    }

    const publicPwaCard = path.match(
      /^\/api\/public\/pwa\/cards\/([0-9a-f-]{36})\/([^/]+)$/i,
    );
    if (req.method === "POST" && path === "/api/public/pwa/claim") {
      const body = await req.json();
      const businessId = safeId(String(body.businessId || ""));
      const customerId = safeId(String(body.customerId || ""));
      const cardId = safeId(String(body.cardId || ""));
      const deviceToken = String(body.deviceToken || "");
      const claimToken = String(body.claimToken || "");
      const legacyToken = String(body.legacyToken || "");
      if (!businessId || !customerId || deviceToken.length < 32) {
        return response({ message: "Activación no válida" }, 400);
      }
      const { data: customerRow } = await admin.from("customers")
        .select("id,pwa_access_token,pwa_device_token_hash,pwa_claim_token_hash,pwa_claim_expires_at,deleted_at")
        .eq("business_id", businessId)
        .eq("id", customerId)
        .maybeSingle();
      if (!customerRow || customerRow.deleted_at) return response({ message: "Tarjeta no encontrada" }, 404);
      const { data: enrollment } = cardId
        ? await admin.from("customer_card_enrollments")
          .select("card_id,device_token_hash,claim_token_hash,claim_expires_at")
          .eq("business_id", businessId)
          .eq("customer_id", customerId)
          .eq("card_id", cardId)
          .maybeSingle()
        : { data: null };
      const deviceHash = await sha256Hex(deviceToken);
      const registeredDeviceHash = enrollment?.device_token_hash || customerRow.pwa_device_token_hash;
      if (registeredDeviceHash === deviceHash) {
        if (claimToken) {
          const suppliedClaimHash = await sha256Hex(claimToken);
          const storedClaimHash = enrollment?.claim_token_hash || customerRow.pwa_claim_token_hash;
          if (storedClaimHash === suppliedClaimHash) {
            if (enrollment) {
              await admin.from("customer_card_enrollments").update({
                claim_token_hash: null,
                claim_expires_at: null,
                updated_at: new Date().toISOString(),
              }).eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId);
            } else {
              await admin.from("customers").update({
                pwa_claim_token_hash: null,
                pwa_claim_expires_at: null,
                updated_at: new Date().toISOString(),
              }).eq("business_id", businessId).eq("id", customerId);
            }
          }
        }
        if (cardId) {
          await linkCardToCustomerDevices(businessId, customerId, cardId, deviceHash);
        }
        return response({
          ok: true,
          realtimeTopic: pwaRealtimeTopic(businessId, customerId, deviceHash, cardId),
        });
      }
      const claimHash = claimToken ? await sha256Hex(claimToken) : "";
      const claimValid = Boolean(
        claimHash && (enrollment?.claim_token_hash || customerRow.pwa_claim_token_hash) === claimHash &&
        (enrollment?.claim_expires_at || customerRow.pwa_claim_expires_at) &&
        new Date(enrollment?.claim_expires_at || customerRow.pwa_claim_expires_at).getTime() > Date.now()
      );
      const legacyValid = Boolean(
        !customerRow.pwa_device_token_hash && legacyToken && legacyToken === customerRow.pwa_access_token
      );
      if (!claimValid && !legacyValid) {
        return response({
          message: registeredDeviceHash
            ? "Esta tarjeta ya está vinculada a otro dispositivo"
            : "Este enlace ya no puede activar la tarjeta",
        }, registeredDeviceHash ? 409 : 403);
      }
      const { error } = enrollment
        ? await admin.from("customer_card_enrollments").update({
          device_token_hash: deviceHash,
          claim_token_hash: null,
          claim_expires_at: null,
          updated_at: new Date().toISOString(),
        }).eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId)
        : await admin.from("customers").update({
          pwa_device_token_hash: deviceHash,
          pwa_claim_token_hash: null,
          pwa_claim_expires_at: null,
          updated_at: new Date().toISOString(),
        }).eq("business_id", businessId).eq("id", customerId);
      if (error) throw error;
      if (cardId) {
        await linkCardToCustomerDevices(businessId, customerId, cardId, deviceHash);
      }
      return response({
        ok: true,
        realtimeTopic: pwaRealtimeTopic(businessId, customerId, deviceHash, cardId),
      });
    }

    if (req.method === "POST" && path === "/api/public/pwa/install-ticket") {
      const body = await req.json();
      const businessId = safeId(String(body.businessId || ""));
      const customerId = safeId(String(body.customerId || ""));
      const cardId = safeId(String(body.cardId || ""));
      const customerRow = await authorizedPwaCustomer(req, businessId, customerId, cardId);
      if (!customerRow || customerRow.deleted_at) return response({ message: "Tarjeta no encontrada" }, 404);
      const installTicket = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
      const { error } = cardId
        ? await admin.from("customer_card_enrollments").update({
          claim_token_hash: await sha256Hex(installTicket),
          claim_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId)
        : await admin.from("customers").update({
          pwa_claim_token_hash: await sha256Hex(installTicket),
          pwa_claim_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("business_id", businessId).eq("id", customerId);
      if (error) throw error;
      return response({ installTicket, expiresInSeconds: 900 });
    }

    if (req.method === "GET" && publicPwaCard) {
      const businessId = publicPwaCard[1];
      const customerId = safeId(decodeURIComponent(publicPwaCard[2]));
      const cardId = safeId(String(url.searchParams.get("card") || ""));
      const [{ data: businessRow }, customerRow] = await Promise.all([
        admin.from("businesses").select("*").eq("id", businessId).maybeSingle(),
        authorizedPwaCustomer(req, businessId, customerId, cardId),
      ]);
      if (!businessRow || !customerRow) {
        return response({ message: "Tarjeta no encontrada" }, 404);
      }
      const requestDeviceToken = String(req.headers.get("x-fideli-device-token") || "");
      const requestDeviceHash = requestDeviceToken.length >= 32
        ? await sha256Hex(requestDeviceToken)
        : "";
      // Una tarjeta solo pertenece al dispositivo que la activo. Nunca copiamos
      // automaticamente todas las tarjetas de un cliente a un dispositivo nuevo:
      // conocer su correo y telefono no debe dar acceso a sus otros pases.
      let enrollmentQuery = admin
        .from("customer_card_devices")
        .select("card_id,created_at")
        .eq("business_id", businessId)
        .eq("customer_id", customerId);
      if (requestDeviceHash) {
        enrollmentQuery = enrollmentQuery.eq("device_token_hash", requestDeviceHash);
      } else {
        enrollmentQuery = enrollmentQuery.eq("card_id", cardId);
      }
      const { data: deviceEnrollments, error: enrollmentError } = await enrollmentQuery
        .order("created_at", { ascending: true });
      if (enrollmentError) throw enrollmentError;
      const enrolledCardIds = [...new Set(
        (deviceEnrollments || []).map((item) => String(item.card_id)),
      )];
      const effectiveCardId = enrolledCardIds.includes(cardId)
        ? cardId
        : (enrolledCardIds[0] || cardId);
      const cardRow = effectiveCardId
        ? await loyaltyCard(businessId, effectiveCardId)
        : await loyaltyCard(businessId);
      if (!cardRow) return response({ message: "Tarjeta no encontrada" }, 404);
      const cardExpired = Boolean(
        cardRow.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now(),
      );
      const cardUnavailable = cardRow.active === false || cardExpired;
      const appleWalletUrl = new URL(`${functionBaseUrl}/api/wallet/apple/${encodeURIComponent(customerId)}`);
      appleWalletUrl.searchParams.set("card", cardRow.id);
      const allowsPersonalSharing =
        (cardRow.program_type === "points" || cardRow.program_type === "stamps") &&
        cardRow.card_kind !== "Tarjeta de regalo";
      const qrSvg = !customerRow.deleted_at && !cardUnavailable
        ? await QRCode.toString(customerQrPayload(
            customerId,
            cardRow.id,
            await qrTokenForCard(customerRow as Customer, cardRow),
          ), {
            type: "svg", width: 512, margin: 2, errorCorrectionLevel: "M",
            color: { dark: "#000000", light: "#ffffff" },
          })
        : null;
      const { data: enrolledCards } = enrolledCardIds.length
        ? await admin.from("loyalty_cards").select("*")
          .eq("business_id", businessId)
          .in("id", enrolledCardIds)
          .neq("card_kind", "Evento")
        : { data: [] };
      const cardsById = new Map(
        ((enrolledCards || []) as LoyaltyCard[]).map((item) => [item.id, item]),
      );
      const cards = await Promise.all(enrolledCardIds.flatMap((enrolledCardId) => {
        const enrolledCard = cardsById.get(enrolledCardId);
        if (!enrolledCard) return [];
        return [async () => {
          const enrolledExpired = Boolean(
            enrolledCard.expires_at && new Date(enrolledCard.expires_at).getTime() <= Date.now(),
          );
          const enrolledUnavailable = enrolledCard.active === false || enrolledExpired;
          const enrolledSharing =
            (enrolledCard.program_type === "points" || enrolledCard.program_type === "stamps") &&
            enrolledCard.card_kind !== "Tarjeta de regalo";
          const enrolledQr = !customerRow.deleted_at && !enrolledUnavailable
            ? await QRCode.toString(customerQrPayload(
              customerId,
              enrolledCard.id,
              await qrTokenForCard(customerRow as Customer, enrolledCard),
            ), {
              type: "svg", width: 512, margin: 2, errorCorrectionLevel: "M",
              color: { dark: "#000000", light: "#ffffff" },
            })
            : null;
          const enrolledAppleUrl = new URL(
            `${functionBaseUrl}/api/wallet/apple/${encodeURIComponent(customerId)}`,
          );
          enrolledAppleUrl.searchParams.set("card", enrolledCard.id);
          return {
            cardId: enrolledCard.id,
            card: publicCardPayload(businessRow, enrolledCard, customerRow as Customer),
            qrDataUrl: enrolledQr
              ? `data:image/svg+xml;base64,${Buffer.from(enrolledQr).toString("base64")}`
              : null,
            personalSharingAllowed: enrolledSharing,
            appleWalletUrl: customerRow.deleted_at || enrolledUnavailable
              ? null
              : enrolledAppleUrl.toString(),
            googleWalletUrl: customerRow.deleted_at || enrolledUnavailable
              ? null
              : googleEnrollmentUrl(customerRow.id, enrolledCard.id),
            realtimeTopic: requestDeviceHash
              ? pwaRealtimeTopic(businessId, customerId, requestDeviceHash, enrolledCard.id)
              : null,
          };
        }];
      }).map((build) => build()));
      return response({
        business: {
          id: businessRow.id,
          name: businessRow.name,
          colorHex: businessRow.color_hex,
          locations: businessLocations(businessRow),
        },
        customer: {
          id: customerRow.id,
          name: customerRow.name,
          code: customerRow.referral_code,
        },
        deleted: Boolean(customerRow.deleted_at),
        cardId: cardRow.id,
        card: publicCardPayload(businessRow, cardRow, customerRow as Customer),
        qrDataUrl: qrSvg ? `data:image/svg+xml;base64,${Buffer.from(qrSvg).toString("base64")}` : null,
        personalSharingAllowed: allowsPersonalSharing,
        appleWalletUrl: customerRow.deleted_at || cardUnavailable ? null : appleWalletUrl.toString(),
        googleWalletUrl: customerRow.deleted_at || cardUnavailable
          ? null
          : googleEnrollmentUrl(customerRow.id, cardRow.id),
        realtimeTopic: requestDeviceHash
          ? pwaRealtimeTopic(businessId, customerId, requestDeviceHash, cardRow.id)
          : null,
        cards,
        webPushPublicKey: Deno.env.get("WEB_PUSH_PUBLIC_KEY") || null,
      });
    }

    if (req.method === "POST" && path === "/api/public/pwa/subscriptions") {
      const body = await req.json();
      const businessId = safeId(String(body.businessId || ""));
      const customerId = safeId(String(body.customerId || ""));
      const cardId = safeId(String(body.cardId || ""));
      const endpoint = String(body.subscription?.endpoint || "").slice(0, 4096);
      const p256dh = String(body.subscription?.keys?.p256dh || "").slice(0, 512);
      const auth = String(body.subscription?.keys?.auth || "").slice(0, 512);
      const customerRow = await authorizedPwaCustomer(req, businessId, customerId, cardId);
      if (!customerRow || customerRow.deleted_at) {
        return response({ message: "Tarjeta no encontrada" }, 404);
      }
      if (!endpoint || !p256dh || !auth) return response({ message: "Suscripción no válida" }, 400);
      const { error } = await admin.from("web_push_subscriptions").upsert({
        business_id: businessId,
        customer_id: customerId,
        card_id: cardId || null,
        endpoint,
        p256dh,
        auth,
        user_agent: String(req.headers.get("user-agent") || "").slice(0, 500),
        updated_at: new Date().toISOString(),
      }, { onConflict: "business_id,endpoint" });
      if (error) throw error;
      return response({ ok: true });
    }

    if (req.method === "DELETE" && path === "/api/public/pwa/subscriptions") {
      const body = await req.json();
      const businessId = safeId(String(body.businessId || ""));
      const customerId = safeId(String(body.customerId || ""));
      const cardId = safeId(String(body.cardId || ""));
      const endpoint = String(body.endpoint || "").slice(0, 4096);
      const customerRow = await authorizedPwaCustomer(req, businessId, customerId, cardId);
      if (!customerRow) {
        return response({ message: "Tarjeta no encontrada" }, 404);
      }
      if (endpoint) {
        const { error } = await admin
          .from("web_push_subscriptions")
          .delete()
          .eq("business_id", businessId)
          .eq("customer_id", customerId)
          .eq("endpoint", endpoint);
        if (error) throw error;
      }
      return response({ ok: true });
    }

    const publicClub = path.match(/^\/club\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && publicClub) {
      const businessRow = await business(publicClub[1]);
      const location = publicClubForBusiness(
        publicClub[1],
        String(businessRow.public_slug || ""),
      );
      return new Response(null, { status: 302, headers: { location: location.toString() } });
    }

    const publicWalletStatus = path.match(
      /^\/api\/public\/clubs\/([0-9a-f-]{36})\/customers\/([^/]+)\/wallet-status$/i,
    );
    if (req.method === "GET" && publicWalletStatus) {
      const businessId = publicWalletStatus[1];
      const customerId = safeId(publicWalletStatus[2]);
      const cardId = url.searchParams.get("card")
        ? safeId(url.searchParams.get("card")!)
        : null;
      const serial = cardId ? `${customerId}--${cardId}` : customerId;
      const [{ data: customerRow }, { count }] = await Promise.all([
        admin
          .from("customers")
          .select("id")
          .eq("business_id", businessId)
          .eq("id", customerId)
          .is("deleted_at", null)
          .maybeSingle(),
        admin
          .from("wallet_registrations")
          .select("serial_number", { count: "exact", head: true })
          .eq("serial_number", serial),
      ]);
      if (!customerRow) return response({ message: "Cliente no encontrado" }, 404);
      return response({ installed: Number(count || 0) > 0 });
    }

    const publicRegistration = path.match(/^\/api\/public\/clubs\/([0-9a-f-]{36})\/register$/i);
    const publicAvailability = path.match(/^\/api\/public\/clubs\/([0-9a-f-]{36})\/registration-availability$/i);
    if (req.method === "GET" && publicAvailability) {
      const businessId = publicAvailability[1];
      const phoneDigits = String(url.searchParams.get("phone") || "").replace(/\D/g, "").slice(0, 40);
      const email = String(url.searchParams.get("email") || "").trim().toLowerCase().slice(0, 160);
      const cardId = safeId(String(url.searchParams.get("cardId") || ""));
      const [phoneMatch, { data: emailOwner }] = await Promise.all([
        phoneDigits.length >= 7
          ? customerByPhone(businessId, phoneDigits, "id,pwa_device_token_hash,card_balances")
          : Promise.resolve({ customer: null, found: false, ambiguous: false }),
        /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
          ? admin.from("customers").select("id,pwa_device_token_hash,card_balances").eq("business_id", businessId)
            .eq("email", email).is("deleted_at", null).limit(1).maybeSingle()
          : Promise.resolve({ data: null }),
      ]);
      const phoneOwner = phoneMatch.customer;
      const sameOwner = phoneOwner && emailOwner
        ? phoneOwner.id === emailOwner.id ? phoneOwner : null
        : (phoneOwner || emailOwner || null);
      const selectedCard = cardId ? await loyaltyCard(businessId, cardId) : null;
      const conflict = await registrationConflict(
        businessId,
        sameOwner?.id,
        selectedCard,
      );
      const mayAddCard = Boolean(
        sameOwner &&
        selectedCard &&
        !conflict.duplicateCard &&
        !conflict.duplicateCategory
      );
      return response({
        phoneUsed: phoneMatch.found && !mayAddCard,
        emailUsed: Boolean(emailOwner) && !mayAddCard,
        existingCustomer: mayAddCard,
        duplicateCard: conflict.duplicateCard,
        duplicateCategory: conflict.duplicateCategory,
        identityMismatch: Boolean(phoneMatch.found && emailOwner && !sameOwner),
        category: registrationCategory(selectedCard),
      });
    }

    if (req.method === "POST" && publicRegistration) {
      const businessId = publicRegistration[1];
      const expectsJson = req.headers.get("content-type")?.includes("application/json") ?? false;
      const submitted = expectsJson
        ? await req.json()
        : Object.fromEntries(await req.formData());
      if (String(submitted.website || "").trim()) return response({ message: "Solicitud rechazada" }, 400);
      const name = String(submitted.name || "").trim().slice(0, 120);
      const phone = String(submitted.phone || "").trim().slice(0, 40);
      const email = String(submitted.email || "").trim().toLowerCase().slice(0, 160);
      const registrationDeviceToken = String(submitted.deviceToken || "");
      const hasRegistrationDevice = registrationDeviceToken.length >= 32;
      const birthDate = /^\d{4}-\d{2}-\d{2}$/.test(String(submitted.birthDate || ""))
        ? String(submitted.birthDate)
        : null;
      const phoneDigits = phone.replace(/\D/g, "");
      const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
      const cardId = safeId(String(submitted.cardId || ""));
      const referredBy = String(submitted.referredBy || "")
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, "")
        .slice(0, 80);
      const { data: businessRow } = await admin
        .from("businesses")
        .select("id,name,color_hex,wallet_icon_path,wallet_logo_path")
        .eq("id", businessId)
        .maybeSingle();
      if (!businessRow || name.length < 2 || phoneDigits.length < 7 || !validEmail) {
        const message = name.length < 2
          ? "Escribe un nombre válido"
          : phoneDigits.length < 7
          ? "Escribe un teléfono válido"
          : "Escribe un correo electrónico válido";
        if (expectsJson) return response({ message }, 400);
        return htmlResponse(clubLayout("Datos incompletos", businessRow?.color_hex || "#6750A4", `<h1>Revisa tus datos</h1><p>${message}.</p>`), 400);
      }
      const selectedCard = cardId ? await loyaltyCard(businessId, cardId) : await loyaltyCard(businessId);
      if (selectedCard && (!selectedCard.active || (selectedCard.expires_at && new Date(selectedCard.expires_at).getTime() <= Date.now()))) {
        return response({ message: "Esta tarjeta ya no está disponible" }, 410);
      }

      const registrationDeviceHash = hasRegistrationDevice
        ? await sha256Hex(registrationDeviceToken)
        : null;
      const [phoneMatch, { data: emailOwner }] = await Promise.all([
        customerByPhone(businessId, phoneDigits),
        admin.from("customers").select("*").eq("business_id", businessId)
          .eq("email", email).is("deleted_at", null).limit(1).maybeSingle(),
      ]);
      const phoneOwner = phoneMatch.customer;
      const existingCustomer = (phoneOwner && emailOwner
        ? phoneOwner.id === emailOwner.id ? phoneOwner : null
        : (phoneOwner || emailOwner || null)) as Customer | null;
      const existingBalances = {
        ...(existingCustomer?.card_balances || {}),
      } as Record<string, { points?: number; stamps?: number; visits?: number }>;
      const conflict = await registrationConflict(
        businessId,
        existingCustomer?.id,
        selectedCard,
      );
      const mayAddToExisting = Boolean(
        existingCustomer &&
        selectedCard &&
        registrationDeviceHash &&
        !conflict.duplicateCard &&
        !conflict.duplicateCategory
      );
      if ((phoneMatch.found || emailOwner) && !mayAddToExisting) {
        const categoryName = registrationCategoryName(selectedCard);
        return response({
          message: conflict.duplicateCard
            ? "Esta persona ya tiene agregada esta tarjeta"
            : conflict.duplicateCategory
            ? `Esta persona ya tiene ${categoryName} en este comercio`
            : phoneMatch.ambiguous
            ? "Hay más de un perfil histórico con ese teléfono. El comercio debe unificarlos antes de agregar otra tarjeta"
            : phoneOwner && emailOwner
            ? "El teléfono y el correo pertenecen a perfiles diferentes. Revisa los datos"
            : phoneMatch.found
            ? "Ese teléfono ya está registrado"
            : "Ese correo ya está registrado",
          code: "CUSTOMER_ALREADY_EXISTS",
          fields: { phone: phoneMatch.found, email: Boolean(emailOwner) },
          duplicateCard: conflict.duplicateCard,
          duplicateCategory: conflict.duplicateCategory,
        }, 409);
      }

      const serial = existingCustomer?.id || `customer-${crypto.randomUUID()}`;
      const referral = existingCustomer?.referral_code ||
        crypto.randomUUID().replaceAll("-", "").slice(0, 8).toUpperCase();
      const pwaAccessToken = existingCustomer?.pwa_access_token ||
        crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "").slice(0, 16);
      const pwaClaimToken = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
      const pwaInstallTicket = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
      const cardBalances = { ...existingBalances };
      if (selectedCard) {
        cardBalances[selectedCard.id] = { points: 0, stamps: 0, visits: 0 };
      }
      const customerPayload = {
          pwa_claim_token_hash: await sha256Hex(
            hasRegistrationDevice ? pwaInstallTicket : pwaClaimToken,
          ),
          pwa_claim_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          card_balances: cardBalances,
          updated_at: new Date().toISOString(),
      };
      let enrollmentCreated = false;
      const enrollmentPayload = selectedCard
        ? {
          business_id: businessId,
          customer_id: serial,
          card_id: selectedCard.id,
          category: registrationCategory(selectedCard),
          device_token_hash: registrationDeviceHash,
          claim_token_hash: await sha256Hex(
            hasRegistrationDevice ? pwaInstallTicket : pwaClaimToken,
          ),
          claim_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          updated_at: new Date().toISOString(),
        }
        : null;
      // Para un cliente existente reservamos primero la categoria. Asi dos
      // solicitudes simultaneas no escriben saldo ni dejan una tarjeta fantasma.
      if (existingCustomer && enrollmentPayload) {
        const { error: reserveError } = await admin
          .from("customer_card_enrollments")
          .insert(enrollmentPayload);
        if (reserveError?.code === "23505") {
          return response({
            message: `Esta persona ya tiene ${registrationCategoryName(selectedCard)} en este comercio`,
            code: "CARD_CATEGORY_ALREADY_EXISTS",
            fields: { phone: true, email: true },
            duplicateCategory: true,
          }, 409);
        }
        if (reserveError) throw reserveError;
        enrollmentCreated = true;
      }
      const { error } = existingCustomer
        ? await admin.from("customers").update(customerPayload)
          .eq("business_id", businessId).eq("id", existingCustomer.id)
        : await admin.from("customers").insert({
          id: serial,
          business_id: businessId,
          name,
          phone,
          phone_normalized: phoneDigits,
          registration_phone_key: `${businessId}:${phoneDigits}`,
          email,
          registration_email_key: `${businessId}:${email}`,
          birth_date: birthDate,
          points: 0,
          stamps: 0,
          visits: 0,
          tier: "",
          referral_code: referral,
          pwa_access_token: pwaAccessToken,
          pwa_device_token_hash: registrationDeviceHash,
          ...customerPayload,
        });
        if (error) {
          if (enrollmentCreated && selectedCard) {
            await admin.from("customer_card_enrollments").delete()
              .eq("business_id", businessId)
              .eq("customer_id", serial)
              .eq("card_id", selectedCard.id);
          }
        }
        if (error?.code === "23505") {
          return response({
            message: "Ese teléfono o correo ya está registrado",
            code: "CUSTOMER_ALREADY_EXISTS",
            fields: { phone: true, email: true },
          }, 409);
        }
        if (error) throw error;
        if (selectedCard && !enrollmentCreated) {
          const { error: enrollmentError } = await admin
            .from("customer_card_enrollments")
            .insert({
              business_id: businessId,
              customer_id: serial,
              card_id: selectedCard.id,
              category: registrationCategory(selectedCard),
              device_token_hash: registrationDeviceHash,
              claim_token_hash: await sha256Hex(
                hasRegistrationDevice ? pwaInstallTicket : pwaClaimToken,
              ),
              claim_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
              updated_at: new Date().toISOString(),
            });
          if (enrollmentError?.code === "23505") {
            if (!existingCustomer) {
              await admin.from("customers").delete()
                .eq("business_id", businessId)
                .eq("id", serial);
            }
            return response({
              message: `Esta persona ya tiene ${registrationCategoryName(selectedCard)} en este comercio`,
              code: "CARD_CATEGORY_ALREADY_EXISTS",
              fields: { phone: true, email: true },
              duplicateCategory: true,
            }, 409);
          }
          if (enrollmentError) {
            if (!existingCustomer) {
              await admin.from("customers").delete()
                .eq("business_id", businessId)
                .eq("id", serial);
            }
            throw enrollmentError;
          }
        }
        if (selectedCard) {
          await linkCardToCustomerDevices(
            businessId,
            serial,
            selectedCard.id,
            registrationDeviceHash,
          );
        }
        if (!existingCustomer && referredBy) {
          const { data: referrer } = await admin
            .from("customers")
            .select("id,points,card_balances")
            .eq("business_id", businessId)
            .eq("referral_code", referredBy)
            .is("deleted_at", null)
            .neq("id", serial)
            .maybeSingle();
          if (referrer) {
            const balances = { ...(referrer.card_balances || {}) } as Record<
              string,
              { points?: number; stamps?: number; visits?: number }
            >;
            if (selectedCard) {
              const current = balances[selectedCard.id] || {};
              balances[selectedCard.id] = {
                ...current,
                points: Number(current.points || 0) + 50,
              };
            }
            const { error: referralError } = await admin
              .from("customers")
              .update({
                points: Number(referrer.points || 0) + 50,
                card_balances: balances,
                wallet_message: walletNotificationValue("🎉 ¡Un amigo se registró con tu QR! Ganaste 50 puntos."),
                updated_at: new Date().toISOString(),
              })
              .eq("business_id", businessId)
              .eq("id", referrer.id);
            if (referralError) throw referralError;
            await admin.from("loyalty_events").insert({
              id: `activity-${crypto.randomUUID()}`,
              business_id: businessId,
              customer_id: referrer.id,
              description: `Referido registrado: ${name}`,
              points_delta: 50,
              event_type: "referral",
              program_id: selectedCard?.id || null,
              metadata: { referred_customer_id: serial },
            });
            const { data: referrerPasses } = await admin
              .from("wallet_passes")
              .select("serial_number")
              .eq("business_id", businessId)
              .eq("customer_id", referrer.id);
            const referrerSerials = (referrerPasses || []).map(
              (item) => item.serial_number as string,
            );
            if (referrerSerials.length) {
              const walletUpdatedAt = new Date().toISOString();
              const { error: passUpdateError } = await admin
                .from("wallet_passes")
                .update({
                  update_tag: Date.now(),
                  updated_at: walletUpdatedAt,
                })
                .in("serial_number", referrerSerials)
                .eq("business_id", businessId);
              if (passUpdateError) throw passUpdateError;
              notifyPassesInBackground(referrerSerials);
            }
          }
        }
      let addedCardNotification: string | null = null;
      if (existingCustomer && selectedCard) {
        const addedLabel = registrationCategory(selectedCard) === "membership"
          ? "Tarjeta de membresía agregada"
          : registrationCategory(selectedCard) === "gift"
          ? "Tarjeta de regalo agregada"
          : "Tarjeta de fidelidad agregada";
        addedCardNotification = addedLabel;
        const notificationValue = walletNotificationValue(addedLabel);
        await admin.from("customers").update({
          wallet_message: notificationValue,
          updated_at: new Date().toISOString(),
        }).eq("business_id", businessId).eq("id", serial);
        const { data: installedPasses } = await admin.from("wallet_passes")
          .select("serial_number")
          .eq("business_id", businessId)
          .eq("customer_id", serial)
          .order("updated_at", { ascending: true })
          .limit(1);
        const primarySerial = String(installedPasses?.[0]?.serial_number || "");
        if (primarySerial) {
          await admin.from("wallet_passes").update({
            update_tag: Date.now(),
            updated_at: new Date().toISOString(),
          }).eq("business_id", businessId).eq("serial_number", primarySerial);
          notifyPassesInBackground([primarySerial]);
        }
        await Promise.all([
          broadcastPwaCardUpdate(businessId, [serial], "card_added"),
          sendWebPush(businessId, [serial], String(businessRow.name || "Fideli"), addedLabel),
        ]);
      }
      const walletUrl = new URL(`${functionBaseUrl}/api/wallet/apple/${encodeURIComponent(serial)}`);
      if (selectedCard) walletUrl.searchParams.set("card", selectedCard.id);
      walletUrl.searchParams.set("v", String(Date.now()));
      const registeredCustomer = await customer(serial);
      if (registeredCustomer && addedCardNotification) {
        const { data: primaryEnrollment } = await admin.from("customer_card_enrollments")
          .select("card_id")
          .eq("business_id", businessId)
          .eq("customer_id", serial)
          .in("category", ["stamps", "points"])
          .limit(1)
          .maybeSingle();
        const primaryCard = primaryEnrollment?.card_id
          ? await loyaltyCard(businessId, String(primaryEnrollment.card_id))
          : null;
        if (primaryCard) {
          await updateGoogleCard(registeredCustomer, primaryCard, addedCardNotification)
            .catch((error) => console.error("Google primary card notification failed", error));
        }
      }
      const googleWalletUrl = registeredCustomer
        ? googleEnrollmentUrl(registeredCustomer.id, selectedCard?.id)
        : null;
      if (expectsJson) {
        return response({
          ok: true,
          customerId: serial,
          referralCode: referral,
          appleWalletUrl: walletUrl.toString(),
          googleWalletUrl,
          pwaClaimToken: hasRegistrationDevice ? null : pwaClaimToken,
          pwaInstallTicket: hasRegistrationDevice ? pwaInstallTicket : null,
          realtimeTopic: registrationDeviceHash && selectedCard
            ? pwaRealtimeTopic(businessId, serial, registrationDeviceHash, selectedCard.id)
            : null,
          webPushPublicKey: Deno.env.get("WEB_PUSH_PUBLIC_KEY") || null,
          business: { id: businessRow.id, name: businessRow.name, colorHex: businessRow.color_hex },
          customer: {
            id: registeredCustomer?.id || serial,
            name: registeredCustomer?.name || name,
            code: referral,
          },
          card: publicCardPayload(businessRow, selectedCard, registeredCustomer),
          cardName: selectedCard?.name || "Tarjeta de fidelidad",
          welcomeMessage: selectedCard?.welcome_message?.trim()
            .replaceAll("{nombre}", registeredCustomer?.name || name) || `¡Bienvenido a ${businessRow.name}!`,
        });
      }
      const isAndroid = /android/i.test(req.headers.get("user-agent") || "");
      const directWalletUrl = isAndroid ? googleWalletUrl : walletUrl.toString();
      if (directWalletUrl) {
        return new Response(null, {
          status: 303,
          headers: { location: directWalletUrl },
        });
      }
      return htmlResponse(clubLayout(
        `Tarjeta de ${businessRow.name}`,
        businessRow.color_hex,
        "<h1>Google Wallet aún no está configurado</h1><p>La tarjeta fue creada, pero falta activar Google Wallet para poder agregarla en Android.</p>",
      ), 503);
    }

    const privateCardQrValidation = path.match(
      /^\/api\/customers\/([^/]+)\/cards\/([^/]+)\/validate-qr$/,
    );
    if (req.method === "POST" && privateCardQrValidation) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const customerId = safeId(privateCardQrValidation[1]);
      const cardId = safeId(privateCardQrValidation[2]);
      const submitted = await req.json().catch(() => ({}));
      const token = String(submitted.token || "");
      const { data: membership } = await admin.from("business_members")
        .select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const [{ data: customerRow }, { data: enrollment }, cardRow] = await Promise.all([
        admin.from("customers").select("id,pwa_access_token,deleted_at")
          .eq("business_id", membership.business_id).eq("id", customerId).maybeSingle(),
        admin.from("customer_card_enrollments").select("card_id,category")
          .eq("business_id", membership.business_id).eq("customer_id", customerId)
          .eq("card_id", cardId).maybeSingle(),
        loyaltyCard(membership.business_id, cardId),
      ]);
      if (!customerRow || customerRow.deleted_at || !enrollment || !cardRow) {
        return response({ message: "Tarjeta no encontrada" }, 404);
      }
      const expectedToken = await qrTokenForCard(
        { ...customerRow, business_id: membership.business_id } as Customer,
        cardRow,
      );
      if (token.length < 32 || token !== expectedToken) {
        return response({ message: "Código privado no válido" }, 403);
      }
      const expired = Boolean(
        cardRow.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now(),
      );
      if (cardRow.active === false || expired) {
        return response({
          ok: false,
          status: expired ? "expired" : "blocked",
          message: cardRow.program_type === "membership"
            ? expired ? "Membresía vencida" : "Membresía bloqueada"
            : expired ? "Tarjeta vencida" : "Tarjeta bloqueada",
        }, 410);
      }
      return response({ ok: true, status: "active", category: enrollment.category });
    }

    const customerCardBalanceMatch = path.match(
      /^\/api\/customers\/([^/]+)\/card-balance$/,
    );
    if (req.method === "POST" && customerCardBalanceMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const customerId = safeId(customerCardBalanceMatch[1]);
      const submitted = await req.json();
      const programId = safeId(String(submitted.programId || ""));
      const requestedValue = Number(submitted.value);
      if (!programId || !Number.isFinite(requestedValue) || requestedValue < 0) {
        return response({ message: "Saldo no válido" }, 400);
      }
      const targetValue = Math.floor(requestedValue);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const [{ data: currentRow }, cardRow] = await Promise.all([
        admin
          .from("customers")
          .select("*")
          .eq("business_id", membership.business_id)
          .eq("id", customerId)
          .is("deleted_at", null)
          .maybeSingle(),
        loyaltyCard(membership.business_id, programId),
      ]);
      if (!currentRow) return response({ message: "Cliente no encontrado" }, 404);
      if (!cardRow) return response({ message: "Tarjeta no encontrada" }, 404);
      if (!cardRow.active || (cardRow.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now())) {
        return response({ message: "Esta tarjeta ya no está disponible" }, 410);
      }

      const cardBalances = {
        ...((currentRow.card_balances || {}) as Record<
          string,
          { points?: number; stamps?: number; visits?: number }
        >),
      };
      const cardBalance = { ...(cardBalances[programId] || {}) };
      const balanceKey = cardRow.program_type === "points"
        ? "points"
        : cardRow.program_type === "visits" || cardRow.program_type === "membership"
        ? "visits"
        : "stamps";
      const currentValue = Math.max(0, Number(cardBalance[balanceKey]) || 0);
      const delta = targetValue - currentValue;
      cardBalance[balanceKey] = targetValue;
      cardBalances[programId] = cardBalance;
      const legacyValue = Math.max(
        0,
        (Number(currentRow[balanceKey]) || 0) + delta,
      );
      const now = new Date().toISOString();
      const { data: savedCustomer, error: saveError } = await admin
        .from("customers")
        .update({
          card_balances: cardBalances,
          [balanceKey]: legacyValue,
          last_activity_at: now,
          updated_at: now,
        })
        .eq("business_id", membership.business_id)
        .eq("id", customerId)
        .select("*")
        .single();
      if (saveError) throw saveError;

      const saved = savedCustomer as Customer;
      EdgeRuntime.waitUntil(
        syncRewardClaimsForCustomers(membership.business_id, [saved], [cardRow])
          .catch((error) => console.error("Reward claim sync failed", error)),
      );
      const submittedPreviousValue = Number(submitted.previousValue);
      const progressMessage = cardProgressMessage(
        cardRow,
        saved,
        currentRow as Customer,
        Number.isFinite(submittedPreviousValue) ? submittedPreviousValue : currentValue,
      );
      if (progressMessage) {
        await admin
          .from("customers")
          .update({
            wallet_message: walletNotificationValue(progressMessage),
            updated_at: now,
          })
          .eq("business_id", membership.business_id)
          .eq("id", customerId);
      }

      const serialNumbers = await walletPassSerialsForCard(
        membership.business_id,
        customerId,
        programId,
      );
      if (serialNumbers.length) {
        const { error: passUpdateError } = await admin
          .from("wallet_passes")
          .update({ update_tag: Date.now(), updated_at: now })
          .in("serial_number", serialNumbers)
          .eq("business_id", membership.business_id);
        if (passUpdateError) throw passUpdateError;
      }

      // Dispatch Apple and Google updates as soon as the committed balance and
      // revision are available. Optional PWA/web push work must not hold back
      // Wallet refresh scheduling or the merchant response.
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(Promise.allSettled([
        updateGoogleCard(saved, cardRow, progressMessage || null),
      ]).then((results) => {
        results.forEach((result) => {
          if (result.status === "rejected") console.error("Wallet progress notification failed", result.reason);
        });
      }));
      EdgeRuntime.waitUntil(Promise.allSettled([
        broadcastPwaCardUpdate(membership.business_id, [customerId], "customer_balance_updated"),
        ...(progressMessage
          ? [(async () => {
              const businessRow = await business(membership.business_id);
              await sendWebPush(
                membership.business_id,
                [customerId],
                String(businessRow.name || cardRow.name || "Fideli"),
                progressMessage,
                null,
                programId,
              );
            })()]
          : []),
      ]).then((results) => {
        results.forEach((result) => {
          if (result.status === "rejected") console.error("Post-stamp notification failed", result.reason);
        });
      }));
      return response({
        ok: true,
        value: targetValue,
        customer: savedCustomer,
        queuedPasses: serialNumbers.length,
      });
    }

    const customerCardMatch = path.match(/^\/api\/customers\/([^/]+)\/cards\/([^/]+)$/);
    if (req.method === "DELETE" && customerCardMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const customerId = safeId(customerCardMatch[1]);
      const cardId = safeId(customerCardMatch[2]);
      const { data: membership } = await admin.from("business_members")
        .select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const businessId = String(membership.business_id);
      const [{ data: customerRow }, { data: enrollment }, { data: cardRow }, { data: passes }] =
        await Promise.all([
          admin.from("customers").select("*")
            .eq("business_id", businessId).eq("id", customerId).maybeSingle(),
          admin.from("customer_card_enrollments").select("card_id,device_token_hash")
            .eq("business_id", businessId).eq("customer_id", customerId)
            .eq("card_id", cardId).maybeSingle(),
          admin.from("loyalty_cards").select("*")
            .eq("business_id", businessId).eq("id", cardId).maybeSingle(),
          admin.from("wallet_passes").select("serial_number")
            .eq("business_id", businessId).eq("customer_id", customerId)
            .eq("card_id", cardId),
        ]);
      if (!customerRow || !enrollment || !cardRow) {
        return response({ message: "La tarjeta ya no está asignada a este cliente" }, 404);
      }
      const { data: remainingEnrollments, error: remainingError } = await admin
        .from("customer_card_enrollments").select("card_id,created_at")
        .eq("business_id", businessId).eq("customer_id", customerId)
        .neq("card_id", cardId).order("created_at", { ascending: true });
      if (remainingError) throw remainingError;
      const remainingCardIds = (remainingEnrollments || []).map((item) => String(item.card_id));
      const serialNumbers = (passes || []).map((item) => String(item.serial_number));
      const balances = {
        ...((customerRow.card_balances && typeof customerRow.card_balances === "object")
          ? customerRow.card_balances
          : {}),
      } as Record<string, unknown>;
      delete balances[cardId];
      const now = new Date().toISOString();
      if (serialNumbers.length) await notifyPasses(serialNumbers);
      const subscriptionCleanup = remainingCardIds.length
        ? admin.from("web_push_subscriptions").update({
          card_id: remainingCardIds[0],
          updated_at: now,
        }).eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId)
        : admin.from("web_push_subscriptions").delete()
          .eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId);
      const operations = [
        admin.from("loyalty_events").delete()
          .eq("business_id", businessId).eq("customer_id", customerId).eq("program_id", cardId),
        admin.from("customer_card_enrollments").delete()
          .eq("business_id", businessId).eq("customer_id", customerId).eq("card_id", cardId),
        admin.from("customers").update({ card_balances: balances, updated_at: now })
          .eq("business_id", businessId).eq("id", customerId),
      ];
      if (serialNumbers.length) {
        operations.push(
          admin.from("wallet_passes").delete()
            .eq("business_id", businessId).in("serial_number", serialNumbers),
        );
      }
      const results = await Promise.all(operations);
      const failed = results.find((item) => item.error);
      if (failed?.error) throw failed.error;
      // Notify while the endpoint still exists. When this is the customer's
      // final card, subscriptionCleanup deletes that endpoint.
      const businessRow = await business(businessId);
      await sendWebPush(
        businessId,
        [customerId],
        String(businessRow.name || "Fideli"),
        `${String(cardRow.name || "Tu tarjeta")} fue eliminada`,
        null,
        cardId,
      );
      const { error: subscriptionCleanupError } = await subscriptionCleanup;
      if (subscriptionCleanupError) throw subscriptionCleanupError;
      const removedDeviceHash = String(enrollment.device_token_hash || "");
      if (removedDeviceHash) {
        await broadcastPwaTopicUpdate(
          pwaRealtimeTopic(businessId, customerId, removedDeviceHash, cardId),
          "customer_card_removed",
        );
      }
      await broadcastPwaCardUpdate(businessId, [customerId], "customer_card_removed");
      if (remainingCardIds.length) {
        const primaryCard = await loyaltyCard(businessId, remainingCardIds[0]);
        if (primaryCard) {
          EdgeRuntime.waitUntil(
            updateGoogleCard(customerRow as Customer, primaryCard, "Se actualizó tu colección de tarjetas")
              .catch((error) => console.error("Google Wallet collection update failed", error)),
          );
        }
      } else {
        EdgeRuntime.waitUntil(
          expireGooglePasses([customerId]).catch((error) => {
            console.error("Google Wallet card removal failed", error);
          }),
        );
      }
      EdgeRuntime.waitUntil(
        cleanupOrphanWalletDevices().catch((error) => {
          console.error("Wallet device cleanup failed", error);
        }),
      );
      return response({
        ok: true,
        deletedCardId: cardId,
        remainingCardIds,
        removedPasses: serialNumbers.length,
      });
    }

    const customerMatch = path.match(/^\/api\/customers\/([^/]+)$/);
    if (req.method === "DELETE" && customerMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const id = safeId(customerMatch[1]);
      const { data: membership } = await admin.from("business_members").select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const { data: passes } = await admin.from("wallet_passes").select("serial_number").eq("business_id", membership.business_id).or(`customer_id.eq.${id},serial_number.eq.${id}`);
      const serialNumbers = (passes || []).map((item) => item.serial_number as string);
      const now = new Date().toISOString();
      const [, { error }] = await Promise.all([
        admin.from("loyalty_events").delete().eq("business_id", membership.business_id).eq("customer_id", id),
        admin.from("customers").update({
          deleted_at: now,
          wallet_message: "Esta tarjeta fue eliminada por el comercio.",
          wallet_campaign_url: null,
          updated_at: now,
        }).eq("business_id", membership.business_id).eq("id", id),
      ]);
      if (error) throw error;
      if (serialNumbers.length) {
        const { error: passError } = await admin
          .from("wallet_passes")
          .update({ update_tag: Date.now(), updated_at: now })
          .in("serial_number", serialNumbers)
          .eq("business_id", membership.business_id);
        if (passError) throw passError;
      }
      const appleResult = await notifyPasses(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, [id], "customer_deleted")
          .catch((error) => console.error("PWA realtime deletion failed", error)),
      );
      EdgeRuntime.waitUntil((async () => {
        const businessRow = await business(membership.business_id);
        await sendWebPush(
          membership.business_id,
          [id],
          String(businessRow.name || "Fideli"),
          "Tarjeta eliminada",
        );
      })().catch((pushError) => console.error("PWA deletion push failed", pushError)));
      EdgeRuntime.waitUntil(
        expireGooglePasses([id]).catch((googleError) => {
          console.error("Google Wallet expiration failed", googleError);
        }),
      );
      return response({
        ok: true,
        deletedCustomers: 1,
        voidedPasses: serialNumbers.length,
        notifiedDevices: appleResult.delivered,
      });
    }

    if (req.method === "DELETE" && path === "/api/customers") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin.from("business_members").select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const { data: customersToDelete } = await admin.from("customers").select("id").eq("business_id", membership.business_id).is("deleted_at", null);
      const { data: passes } = await admin.from("wallet_passes").select("serial_number").eq("business_id", membership.business_id);
      const serialNumbers = (passes || []).map((item) => item.serial_number as string);
      const customerIds = (customersToDelete || []).map((item) => item.id as string);
      const now = new Date().toISOString();
      const [, { error }] = await Promise.all([
        admin.from("loyalty_events").delete().eq("business_id", membership.business_id),
        admin.from("customers").update({
          deleted_at: now,
          wallet_message: "Esta tarjeta fue eliminada por el comercio.",
          wallet_campaign_url: null,
          updated_at: now,
        }).eq("business_id", membership.business_id).is("deleted_at", null),
      ]);
      if (error) throw error;
      if (serialNumbers.length) {
        const { error: passError } = await admin
          .from("wallet_passes")
          .update({ update_tag: Date.now(), updated_at: now })
          .in("serial_number", serialNumbers)
          .eq("business_id", membership.business_id);
        if (passError) throw passError;
      }
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, customerIds, "customers_deleted")
          .catch((error) => console.error("PWA realtime bulk deletion failed", error)),
      );
      EdgeRuntime.waitUntil((async () => {
        const businessRow = await business(membership.business_id);
        await sendWebPush(
          membership.business_id,
          customerIds,
          String(businessRow.name || "Fideli"),
          "Tarjeta eliminada",
        );
      })().catch((pushError) => console.error("PWA bulk deletion push failed", pushError)));
      EdgeRuntime.waitUntil(
        expireGooglePasses(customerIds).catch((googleError) => {
          console.error("Google Wallet bulk expiration failed", googleError);
        }),
      );
      return response({ ok: true, deletedCustomers: customerIds.length, voidedPasses: serialNumbers.length });
    }

    if (req.method === "POST" && customerMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const id = safeId(customerMatch[1]);
      const body = await req.json();
      const { data: membership } = await admin.from("business_members").select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const previousCustomer = await customer(id);
      const values = {
        id,
        business_id: membership.business_id,
        name: String(body.name || "Cliente Fideli").slice(0, 160),
        phone: String(body.phone || "").slice(0, 80),
        email: String(body.email || "").slice(0, 160),
        birth_date: /^\d{4}-\d{2}-\d{2}$/.test(String(body.birthDate || ""))
          ? String(body.birthDate)
          : null,
        points: Math.max(0, Number(body.points) || 0),
        stamps: Math.max(0, Number(body.stamps) || 0),
        visits: Math.max(0, Number(body.visits) || 0),
        tier: String(body.tier || "").slice(0, 80),
        referral_code: String(body.referral || id).slice(0, 80),
        card_balances: typeof body.cardBalances === "object" && body.cardBalances ? body.cardBalances : {},
        ...(body.recordActivity === true
          ? { last_activity_at: new Date().toISOString() }
          : {}),
        deleted_at: null,
        updated_at: new Date().toISOString(),
      };
      const { data: savedCustomer, error } = await admin
        .from("customers")
        .upsert(values, { onConflict: "business_id,id" })
        .select("*")
        .single();
      if (error) throw error;
      const programId = safeId(String(body.programId || ""));
      let pwaMessage: string | null = null;
      if (programId) {
        const [currentCustomer, currentCard] = await Promise.all([
          Promise.resolve(savedCustomer as Customer),
          loyaltyCard(membership.business_id, programId),
        ]);
        if (currentCustomer && currentCard) {
          EdgeRuntime.waitUntil(
            syncRewardClaimsForCustomers(membership.business_id, [currentCustomer], [currentCard])
              .catch((error) => console.error("Reward claim sync failed", error)),
          );
          const submittedPreviousValue = Number(body.previousProgramValue);
          const message = cardProgressMessage(
            currentCard,
            currentCustomer,
            previousCustomer,
            Number.isFinite(submittedPreviousValue) ? submittedPreviousValue : null,
          );
          pwaMessage = message;
          if (message) {
            await admin
              .from("customers")
              .update({
                wallet_message: walletNotificationValue(message),
                updated_at: new Date().toISOString(),
              })
              .eq("business_id", membership.business_id)
              .eq("id", id);
          }
          EdgeRuntime.waitUntil(
            updateGoogleCard(currentCustomer, currentCard, message).catch(
              (googleError) => {
                console.error("Google Wallet progress update failed", googleError);
              },
            ),
          );
        }
      }
      const now = new Date().toISOString();
      let serialNumbers: string[];
      if (programId) {
        serialNumbers = await walletPassSerialsForCard(
          membership.business_id,
          id,
          programId,
        );
      } else {
        const { data: passes, error: passLookupError } = await admin
          .from("wallet_passes")
          .select("serial_number")
          .eq("business_id", membership.business_id)
          .or(`customer_id.eq.${id},serial_number.eq.${id}`);
        if (passLookupError) throw passLookupError;
        serialNumbers = (passes || []).map((item) => item.serial_number as string);
      }
      if (serialNumbers.length) {
        await admin.from("wallet_passes").update({ update_tag: Date.now(), updated_at: now }).in("serial_number", serialNumbers);
      }
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, [id], "customer_updated")
          .catch((error) => console.error("PWA realtime progress failed", error)),
      );
      if (programId && pwaMessage) {
        EdgeRuntime.waitUntil((async () => {
          const businessRow = await business(membership.business_id);
          await sendWebPush(
            membership.business_id,
            [id],
            String(businessRow.name || "Fideli"),
            pwaMessage!,
            null,
            programId,
          );
        })().catch((pushError) => console.error("PWA progress push failed", pushError)));
      }
      return response({
        ok: true,
        customer: values,
        walletUpdateRequested: serialNumbers.length > 0,
        queuedPasses: serialNumbers.length,
      });
    }

    if (req.method === "POST" && path === "/api/rewards/redeem") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id,role")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);

      const body = await req.json();
      const customerId = safeId(String(body.customerId || ""));
      const rewardId = safeId(String(body.rewardId || ""));
      if (!customerId || !rewardId) {
        return response({ message: "Canje no válido" }, 400);
      }

      const { data: redemption, error: redemptionError } = await admin.rpc(
        "redeem_customer_reward",
        {
          p_business_id: membership.business_id,
          p_customer_id: customerId,
          p_reward_id: rewardId,
        },
      );
      if (redemptionError) throw redemptionError;
      const result = (redemption || {}) as Record<string, unknown>;
      if (result.ok !== true) {
        const status = result.code === "already_redeemed" ? 409 : 400;
        return response(result, status);
      }

      await admin.from("customer_reward_claims")
        .update({ claimed_at: new Date().toISOString() })
        .eq("business_id", membership.business_id)
        .eq("customer_id", customerId)
        .eq("reward_id", rewardId)
        .is("claimed_at", null);

      const { data: passes } = await admin
        .from("wallet_passes")
        .select("serial_number")
        .eq("business_id", membership.business_id)
        .eq("customer_id", customerId);
      const serialNumbers = (passes || []).map((item) => item.serial_number as string);
      if (serialNumbers.length) {
        await admin.from("wallet_passes")
          .update({ update_tag: Date.now(), updated_at: new Date().toISOString() })
          .in("serial_number", serialNumbers);
      }
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, [customerId], "reward_redeemed")
          .catch((error) => console.error("PWA reward update failed", error)),
      );
      return response({ ...result, queuedPasses: serialNumbers.length });
    }

    if (req.method === "POST" && path === "/api/rewards/claims/mark") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const body = await req.json().catch(() => ({}));
      const customerId = safeId(String(body.customerId || ""));
      const rewardId = safeId(String(body.rewardId || ""));
      if (!customerId || !rewardId) return response({ message: "Premio no válido" }, 400);
      const { data: claim, error } = await admin.from("customer_reward_claims")
        .update({ claimed_at: new Date().toISOString() })
        .eq("business_id", membership.business_id)
        .eq("customer_id", customerId)
        .eq("reward_id", rewardId)
        .is("claimed_at", null)
        .select("customer_id,reward_id")
        .maybeSingle();
      if (error) throw error;
      if (!claim) return response({ message: "El premio ya fue entregado o no está pendiente" }, 409);
      return response({ ok: true, message: "Premio marcado como entregado" });
    }

    if (req.method === "POST" && path === "/api/rewards/claims/sync") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const [{ data: customers, error: customerError }, { data: cards, error: cardError }] =
        await Promise.all([
          admin.from("customers").select("*")
            .eq("business_id", membership.business_id).is("deleted_at", null),
          admin.from("loyalty_cards").select("*")
            .eq("business_id", membership.business_id).eq("active", true),
        ]);
      if (customerError) throw customerError;
      if (cardError) throw cardError;
      await syncRewardClaimsForCustomers(
        membership.business_id,
        (customers || []) as Customer[],
        (cards || []) as LoyaltyCard[],
      );
      return response({ ok: true });
    }

    const campaignDeleteMatch = path.match(/^\/api\/campaigns\/([a-zA-Z0-9_-]+)$/);
    if (req.method === "DELETE" && campaignDeleteMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const campaignId = safeId(campaignDeleteMatch[1]);
      if (!campaignId) return response({ message: "Campaña no válida" }, 400);
      const { error } = await admin
        .from("module_records")
        .delete()
        .eq("business_id", membership.business_id)
        .eq("module_type", "campaign")
        .eq("record_id", campaignId);
      if (error) throw error;
      return response({ ok: true, deletedCampaigns: 1 });
    }

    if (req.method === "POST" && path === "/api/campaigns/save") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id,role")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);

      const body = await req.json();
      const campaignId = safeId(String(body.id || body.campaignId || ""));
      const campaignName = String(body.name || body.campaignName || "").trim().slice(0, 120);
      const notificationTitle = String(body.notificationTitle || "").trim().slice(0, 80);
      const message = String(body.message || "").trim().slice(0, 120);
      const audience = String(body.audience || "Todos").trim();
      const targetCustomerId = safeId(String(body.targetCustomerId || ""));
      const targetCustomerName = String(body.targetCustomerName || "").trim().slice(0, 160);
      const sentAt = body.sentAt ? String(body.sentAt).trim().slice(0, 40) : null;
      const allowedAudiences = new Set([
        "Todos", "Nuevos", "Preocupantes", "Riesgo",
        "Cumpleañeros de hoy", "Una persona",
        // Keep old saved campaigns and older clients working.
        "Frecuentes", "Regulares", "Ocasionales", "En riesgo", "Inactivos", "Recuperados",
      ]);
      if (!campaignId || !campaignName) {
        return response({ message: "La campaña necesita un nombre" }, 400);
      }
      if (!allowedAudiences.has(audience)) {
        return response({ message: "Público no válido" }, 400);
      }
      if (audience === "Una persona" && !targetCustomerId) {
        return response({ message: "Selecciona un cliente" }, 400);
      }

      const rawCampaignUrl = String(body.linkUrl || "").trim().slice(0, 2048);
      let campaignUrl: string | null = null;
      if (rawCampaignUrl) {
        try {
          const parsed = new URL(rawCampaignUrl);
          if (parsed.protocol !== "https:" && parsed.protocol !== "http:") throw new Error("protocol");
          campaignUrl = parsed.toString();
        } catch {
          return response({ message: "El link no es válido" }, 400);
        }
      }

      const now = new Date().toISOString();
      const { error: campaignSaveError } = await admin
        .from("module_records")
        .upsert({
          business_id: membership.business_id,
          module_type: "campaign",
          record_id: campaignId,
          payload: {
            id: campaignId,
            name: campaignName,
            notificationTitle,
            message,
            audience,
            targetCustomerId: targetCustomerId || null,
            targetCustomerName: targetCustomerName || null,
            linkUrl: campaignUrl,
            sentAt,
            updatedAt: now,
          },
          updated_at: now,
        }, { onConflict: "business_id,module_type,record_id" });
      if (campaignSaveError) throw campaignSaveError;
      return response({ ok: true, campaignId, notificationTitle });
    }

    if (req.method === "POST" && path === "/api/campaigns/send") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id,role")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);

      const body = await req.json();
      const message = String(body.message || "").trim().slice(0, 120);
      const campaignId = safeId(String(body.campaignId || ""));
      const campaignName = String(body.campaignName || "").trim().slice(0, 120);
      const requestedNotificationTitle = String(body.notificationTitle || "").trim().slice(0, 80);
      const businessRow = await business(membership.business_id);
      const notificationTitle = requestedNotificationTitle || String(businessRow.name || "Fideli").trim().slice(0, 80);
      const audience = String(body.audience || "Todos").trim();
      const targetCustomerId = safeId(String(body.targetCustomerId || ""));
      const birthdayDate = String(body.birthdayDate || "").trim();
      const requestId = String(body.requestId || "").trim().slice(0, 180);
      const rawCampaignUrl = String(body.linkUrl || "").trim().slice(0, 2048);
      let campaignUrl: string | null = null;
      if (rawCampaignUrl) {
        try {
          const parsed = new URL(rawCampaignUrl);
          if (parsed.protocol !== "https:" && parsed.protocol !== "http:") throw new Error("protocol");
          campaignUrl = parsed.toString();
        } catch {
          return response({ message: "El link no es válido" }, 400);
        }
      }
      if (!message) return response({ message: "Escribe un mensaje" }, 400);

      // module_records is the source used by the merchant app. Persist the
      // optional campaign title here as well, so sending and saving cannot
      // diverge even when a client reconnects after an offline edit.
      if (campaignId) {
        const { data: storedCampaign } = await admin
          .from("module_records")
          .select("payload")
          .eq("business_id", membership.business_id)
          .eq("module_type", "campaign")
          .eq("record_id", campaignId)
          .maybeSingle();
        const storedPayload = storedCampaign?.payload && typeof storedCampaign.payload === "object"
          ? storedCampaign.payload as Record<string, unknown>
          : {};
        const { error: campaignSaveError } = await admin
          .from("module_records")
          .upsert({
            business_id: membership.business_id,
            module_type: "campaign",
            record_id: campaignId,
            payload: {
              ...storedPayload,
              id: campaignId,
              ...(campaignName ? { name: campaignName } : {}),
              message,
              notificationTitle: requestedNotificationTitle,
              audience,
              targetCustomerId: targetCustomerId || null,
              linkUrl: campaignUrl,
              updatedAt: new Date().toISOString(),
            },
            updated_at: new Date().toISOString(),
          }, { onConflict: "business_id,module_type,record_id" });
        if (campaignSaveError) throw campaignSaveError;
      }

      if (requestId) {
        const { error: reservationError } = await admin
          .from("campaign_requests")
          .insert({
            business_id: membership.business_id,
            request_id: requestId,
            status: "processing",
          });
        if (reservationError?.code === "23505") {
          const { data: previous } = await admin
            .from("campaign_requests")
            .select("status,response_payload")
            .eq("business_id", membership.business_id)
            .eq("request_id", requestId)
            .maybeSingle();
          if (previous?.status === "completed" && previous.response_payload) {
            return response({ ...previous.response_payload, duplicate: true });
          }
          return response(
            { message: "Esta campaña ya se está enviando" },
            409,
          );
        }
        if (reservationError) throw reservationError;
      }

      let targetIds: string[] | null = null;
      const segmentByAudience: Record<string, string> = {
        "Nuevos": "NEW",
        "Preocupantes": "AT_RISK",
        "Riesgo": "INACTIVE",
        // Legacy values remain accepted for already-saved campaigns.
        "Frecuentes": "FREQUENT",
        "Regulares": "REGULAR",
        "Ocasionales": "OCCASIONAL",
        "En riesgo": "AT_RISK",
        "Inactivos": "INACTIVE",
        "Recuperados": "RECOVERED",
      };
      const requestedSegment = segmentByAudience[audience];
      if (requestedSegment) {
        const { data: segmentTargets, error: segmentError } = await admin
          .from("customer_segments")
          .select("customer_id")
          .eq("business_id", membership.business_id)
          .eq("segment_code", requestedSegment);
        if (segmentError) throw segmentError;
        targetIds = (segmentTargets || []).map((item) => item.customer_id as string);
      }

      if (audience === "Cumpleañeros de hoy") {
        const birthdayDateMatch = birthdayDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
        const parsedBirthdayDate = birthdayDateMatch
          ? new Date(`${birthdayDate}T00:00:00.000Z`)
          : null;
        if (
          !birthdayDateMatch ||
          !parsedBirthdayDate ||
          Number.isNaN(parsedBirthdayDate.getTime()) ||
          parsedBirthdayDate.toISOString().slice(0, 10) !== birthdayDate
        ) {
          return response({ message: "No se pudo determinar la fecha de cumpleaños de hoy" }, 400);
        }
        const monthDay = birthdayDate.slice(5);
        const birthdayRows: { id: string; birth_date: string | null }[] = [];
        for (let page = 0; ; page++) {
          const { data: rows, error: birthdayError } = await admin
            .from("customers")
            .select("id,birth_date")
            .eq("business_id", membership.business_id)
            .is("deleted_at", null)
            .range(page * 1000, page * 1000 + 999);
          if (birthdayError) throw birthdayError;
          birthdayRows.push(...((rows || []) as typeof birthdayRows));
          if ((rows || []).length < 1000) break;
        }
        targetIds = birthdayRows
          .filter((item) => item.birth_date?.slice(5, 10) === monthDay)
          .map((item) => item.id);
      }

      let query = admin
        .from("customers")
        .select("id")
        .eq("business_id", membership.business_id)
        .is("deleted_at", null);
      if (targetIds) {
        query = targetIds.length
          ? query.in("id", targetIds)
          : query.eq("id", "__no_segment_targets__");
      } else if (audience === "Una persona") {
        if (!targetCustomerId) {
          return response({ message: "Selecciona un cliente" }, 400);
        }
        query = query.eq("id", targetCustomerId);
      } else if (audience !== "Todos") {
        return response({ message: "Público no válido" }, 400);
      }
      const { data: targets, error: targetError } = await query;
      if (targetError) throw targetError;
      const serials = (targets || []).map((item) => item.id as string);
      if (!serials.length) {
        const result = { ok: true, targetedCustomers: 0, registeredDevices: 0 };
        if (requestId) {
          await admin
            .from("campaign_requests")
            .update({
              status: "completed",
              response_payload: result,
              updated_at: new Date().toISOString(),
            })
            .eq("business_id", membership.business_id)
            .eq("request_id", requestId);
        }
        return response(result);
      }

      const now = new Date().toISOString();
      const tag = Date.now();
      const { error: messageError } = await admin
        .from("customers")
        .update({
          wallet_message: walletNotificationValue(message),
          wallet_campaign_url: campaignUrl,
          updated_at: now,
        })
        .in("id", serials)
        .eq("business_id", membership.business_id);
      if (messageError) throw messageError;
      const campaignEvents = serials.map((customerId) => ({
        id: `campaign-${crypto.randomUUID()}`,
        business_id: membership.business_id,
        customer_id: customerId,
        description: `Promoción enviada: ${campaignName || message}`,
        points_delta: 0,
        event_type: "campaign_sent",
        metadata: {
          campaign_id: campaignId || null,
          campaign_name: campaignName || null,
          notification_title: notificationTitle,
          message,
          link_url: campaignUrl,
          audience,
        },
        created_at: now,
      }));
      const { error: campaignEventError } = await admin
        .from("loyalty_events")
        .insert(campaignEvents);
      if (campaignEventError) throw campaignEventError;
      const { data: targetPasses, error: passLookupError } = await admin
        .from("wallet_passes")
        .select("serial_number")
        .eq("business_id", membership.business_id)
        .in("customer_id", serials);
      if (passLookupError) throw passLookupError;
      const passSerials = (targetPasses || []).map((item) => item.serial_number as string);
      if (passSerials.length) {
        const { error: passError } = await admin
          .from("wallet_passes")
          .update({ update_tag: tag, updated_at: now })
          .in("serial_number", passSerials)
          .eq("business_id", membership.business_id);
        if (passError) throw passError;
      }

      notifyPassesInBackground(passSerials);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, serials, "campaign_updated")
          .catch((error) => console.error("PWA realtime campaign failed", error)),
      );
      EdgeRuntime.waitUntil(
        updateGoogleCampaign(
          membership.business_id,
          serials,
          notificationTitle,
          message,
          campaignUrl,
        ).catch((error) => {
          console.error("Google Wallet campaign update failed", error);
        }),
      );
      EdgeRuntime.waitUntil(sendWebPush(
        membership.business_id,
        serials,
        notificationTitle,
        message,
        campaignUrl,
      ).catch((error) => console.error("Campaign web push failed", error)));
      const result = {
        ok: true,
        targetedCustomers: serials.length,
        queuedPasses: passSerials.length,
      };
      if (requestId) {
        await admin
          .from("campaign_requests")
          .update({
            status: "completed",
            response_payload: result,
            updated_at: new Date().toISOString(),
          })
          .eq("business_id", membership.business_id)
          .eq("request_id", requestId);
      }
      return response(result);
    }

    if (req.method === "POST" && path === "/api/business/refresh-passes") {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin
        .from("business_members")
        .select("business_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const body = await req.json().catch(() => ({}));
      const now = new Date().toISOString();
      const artworkUpdate: Record<string, unknown> = { updated_at: now };
      const iconPath = String(body.walletIconPath || "").slice(0, 240);
      const logoPath = String(body.walletLogoPath || "").slice(0, 240);
      if (Object.prototype.hasOwnProperty.call(body, "walletIconPath")) {
        if (iconPath && !iconPath.startsWith(`${membership.business_id}/wallet/`)) {
          return response({ message: "Ruta de icono no válida" }, 400);
        }
        artworkUpdate.wallet_icon_path = iconPath || null;
      }
      if (Object.prototype.hasOwnProperty.call(body, "walletLogoPath")) {
        if (logoPath && !logoPath.startsWith(`${membership.business_id}/logo/`)) {
          return response({ message: "Ruta de logo no válida" }, 400);
        }
        artworkUpdate.wallet_logo_path = logoPath || null;
      }
      if (typeof body.name === "string" && body.name.trim()) {
        artworkUpdate.name = body.name.trim().slice(0, 120);
      }
      const { error: artworkError } = await admin
        .from("businesses")
        .update(artworkUpdate)
        .eq("id", membership.business_id);
      if (artworkError) throw artworkError;
      const { data: businessArtwork } = await admin
        .from("businesses")
        .select("wallet_icon_path,wallet_logo_path")
        .eq("id", membership.business_id)
        .maybeSingle();
      EdgeRuntime.waitUntil(Promise.all([
        cleanupVersionedArtwork(
          membership.business_id,
          "wallet",
          businessArtwork?.wallet_icon_path,
          ["icon.png", "icon@2x.png", "icon@3x.png"],
        ),
        cleanupVersionedArtwork(
          membership.business_id,
          "logo",
          businessArtwork?.wallet_logo_path,
          ["logo.png", "logo@2x.png", "logo@3x.png"],
        ),
      ]).then(() => undefined));
      const { data: passes } = await admin
        .from("wallet_passes")
        .select("serial_number")
        .eq("business_id", membership.business_id);
      await admin
        .from("wallet_passes")
        .update({ update_tag: Date.now(), updated_at: now })
        .eq("business_id", membership.business_id);
      const serialNumbers = (passes || []).map((item) => item.serial_number as string);
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, null, "business_updated")
          .catch((error) => console.error("PWA realtime business refresh failed", error)),
      );
      EdgeRuntime.waitUntil(
        syncGoogleBusinessDesign(membership.business_id)
          .catch((error) => console.error("Google Wallet business design refresh failed", error)),
      );
      return response({
        ok: true,
        channel: "apple_wallet",
        affectedPasses: passes?.length || 0,
        queuedPasses: serialNumbers.length,
      });
    }

    const cardMatch = path.match(/^\/api\/cards\/([^/]+)$/);
    if ((req.method === "POST" || req.method === "DELETE") && cardMatch) {
      const user = await merchantUser(req);
      if (!user) return response({ message: "Sesión requerida" }, 401);
      const { data: membership } = await admin.from("business_members").select("business_id").eq("user_id", user.id).limit(1).maybeSingle();
      if (!membership) return response({ message: "Comercio no encontrado" }, 403);
      const id = safeId(cardMatch[1]);
      const now = new Date().toISOString();
      if (req.method === "POST") {
        const body = await req.json();
        const requestedCardKind = String(body.cardKind || "Fidelización").slice(0, 80);
        const requestedExpiration = String(body.expiresAt || "").trim() || null;
        const notifyWallet = body.notifyWallet !== false;
        const { data: previousCard } = await admin
          .from("loyalty_cards")
          .select("background_image_path")
          .eq("business_id", membership.business_id)
          .eq("id", id)
          .maybeSingle();
        const values = {
          id,
          business_id: membership.business_id,
          name: String(body.name || "Tarjeta").slice(0, 120),
          card_kind: requestedCardKind,
          program_type: String(body.programType || "stamps").slice(0, 40),
          earning_rate: Math.max(1, Number(body.earningRate) || 1),
          goal: Math.max(1, Number(body.goal) || 7),
          active: body.active !== false,
          color_hex: /^#[0-9a-f]{6}$/i.test(String(body.colorHex || ""))
            ? String(body.colorHex)
            : null,
          background_image_path: String(body.backgroundImagePath || "").slice(0, 240) || null,
          stamp_icon: ["coffee", "pizza", "haircut", "star", "heart", "paw", "check", "gift", "hamburger", "latte", "coffee_beans", "ice_cream", "hair_scissors", "salon_chair", "pet_collar", "pet_bone", "pet_bowl"].includes(String(body.stampIcon))
            ? String(body.stampIcon)
            : "coffee",
          wallet_layout: body.walletLayout === "classic" ? "classic" : "poster",
          welcome_message: String(
            body.welcomeMessage || "¡Bienvenido! Nos alegra tenerte aquí.",
          ).trim().slice(0, 240),
          stamp_notification_message: String(
            body.stampNotificationMessage ?? "¡Ya tienes {sellos} sellos! Sigue así.",
          ).trim().slice(0, 160),
          completion_message: String(
            body.completionMessage ??
              "🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.",
          ).trim().slice(0, 240),
          reward_milestones: Array.isArray(body.rewardMilestones)
            ? body.rewardMilestones.slice(0, 30).map((item: Record<string, unknown>) => ({
                id: safeId(String(item.id || crypto.randomUUID())),
                stamp: Math.max(1, Number(item.stamp) || 1),
                reward: String(item.reward || "").trim().slice(0, 120),
                message: String(item.message || "").trim().slice(0, 240),
              }))
            : [],
          expires_at: requestedExpiration,
          expiration_notice: null,
          expiration_notice_key: null,
          updated_at: now,
        };
        const { error } = await admin.from("loyalty_cards").upsert(values, { onConflict: "business_id,id" });
        if (error) throw error;
        await admin.from("card_expiration_notifications")
          .delete()
          .eq("business_id", membership.business_id)
          .eq("card_id", id);
        if (values.background_image_path) {
          await admin.storage
            .from("business-assets")
            .remove([`${values.background_image_path}/strip@3x.png`]);
        }
        if (previousCard?.background_image_path && previousCard.background_image_path !== values.background_image_path) {
          const { count } = await admin
            .from("loyalty_cards")
            .select("*", { count: "exact", head: true })
            .eq("background_image_path", previousCard.background_image_path);
          if (!count) {
            await removeArtworkFolder(previousCard.background_image_path, ["strip.png", "strip@2x.png", "strip@3x.png"]);
          }
        }
        if (!notifyWallet) {
          return response({ ok: true, affectedPasses: 0, queuedPasses: 0 });
        }
      } else {
        const [{ data: card }, { data: affectedEnrollments }] = await Promise.all([
          admin
            .from("loyalty_cards")
            .select("name,background_image_path")
            .eq("business_id", membership.business_id)
            .eq("id", id)
            .maybeSingle(),
          admin
            .from("customer_card_enrollments")
            .select("customer_id")
            .eq("business_id", membership.business_id)
            .eq("card_id", id),
        ]);
        const affectedCustomerIds = [...new Set(
          (affectedEnrollments || []).map((item) => String(item.customer_id)).filter(Boolean),
        )];
        const { data: passes } = await admin.from("wallet_passes").select("serial_number").eq("business_id", membership.business_id).eq("card_id", id);
        const serialNumbers = (passes || []).map((item) => item.serial_number as string);
        await deletePassRecords(serialNumbers);
        const [programRecordDelete, rewardRecordDelete] = await Promise.all([
          admin.from("module_records").delete().eq("business_id", membership.business_id).eq("module_type", "program").eq("record_id", id),
          admin.from("module_records").delete().eq("business_id", membership.business_id).eq("module_type", "reward").contains("payload", { programId: id }),
        ]);
        if (programRecordDelete.error) throw programRecordDelete.error;
        if (rewardRecordDelete.error) throw rewardRecordDelete.error;
        const { error } = await admin.from("loyalty_cards").delete().eq("business_id", membership.business_id).eq("id", id);
        if (error) throw error;
        if (card?.background_image_path) {
          const { count } = await admin
            .from("loyalty_cards")
            .select("*", { count: "exact", head: true })
            .eq("background_image_path", card.background_image_path);
          if (!count) {
            await removeArtworkFolder(card.background_image_path, ["strip.png", "strip@2x.png", "strip@3x.png"]);
          }
        }
        EdgeRuntime.waitUntil((async () => {
          const businessRow = await business(membership.business_id);
          await Promise.allSettled([
            broadcastPwaCardUpdate(membership.business_id, affectedCustomerIds, "card_deleted"),
            sendWebPush(
              membership.business_id,
              affectedCustomerIds,
              String(businessRow.name || "Fideli"),
              `${String(card?.name || "Tu tarjeta")} fue eliminada`,
              null,
              id,
            ),
          ]);
        })().catch((error) => console.error("PWA card deletion notification failed", error)));
        return response({ ok: true, deletedCards: 1, deletedPasses: serialNumbers.length });
      }
      const { data: passes } = await admin
        .from("wallet_passes")
        .select("serial_number")
        .eq("business_id", membership.business_id)
        .or(`card_id.eq.${id},card_id.is.null`);
      const serialNumbers = (passes || []).map((item) => item.serial_number as string);
      if (serialNumbers.length) {
        await admin
          .from("wallet_passes")
          .update({ update_tag: Date.now(), updated_at: now })
          .in("serial_number", serialNumbers);
      }
      notifyPassesInBackground(serialNumbers);
      EdgeRuntime.waitUntil(
        broadcastPwaCardUpdate(membership.business_id, null, "card_updated")
          .catch((error) => console.error("PWA realtime card update failed", error)),
      );
      EdgeRuntime.waitUntil(
        syncGoogleBusinessDesign(membership.business_id, id)
          .catch((error) => console.error("Google Wallet card design refresh failed", error)),
      );
      return response({
        ok: true,
        affectedPasses: passes?.length || 0,
        queuedPasses: serialNumbers.length,
      });
    }

    const enrollment = path.match(/^\/api\/wallet\/apple\/([^/]+)$/);
    if (req.method === "GET" && enrollment) {
      const customerId = safeId(enrollment[1]);
      const row = await customer(customerId);
      if (!row) return response({ message: "Cliente no encontrado" }, 404);
      if (row.deleted_at) return response({ message: "Este cliente fue eliminado" }, 410);
      const requestedCardId = url.searchParams.get("card") ? safeId(url.searchParams.get("card")!) : null;
      const cardRow = await loyaltyCard(row.business_id, requestedCardId);
      if (requestedCardId && !cardRow) return response({ message: "Tarjeta no encontrada" }, 404);
      if (cardRow && (!cardRow.active || (cardRow.expires_at && new Date(cardRow.expires_at).getTime() <= Date.now()))) {
        return response({ message: "Esta tarjeta ya venció" }, 410);
      }
      const serial = cardRow ? `${customerId}--${safeId(cardRow.id)}` : customerId;
      await admin.from("wallet_passes").upsert({
        serial_number: serial,
        business_id: row.business_id,
        customer_id: customerId,
        card_id: cardRow?.id || null,
        pass_type_identifier: passTypeId,
        authentication_token: await expectedPassToken(serial),
        update_tag: Date.now(),
        updated_at: new Date().toISOString(),
      });
      const bytes = await createPass(row, serial, cardRow);
      return new Response(bytes, {
        status: 200,
        headers: {
          ...cors,
          "content-type": "application/vnd.apple.pkpass",
          "content-disposition": `attachment; filename="${serial}.pkpass"`,
          "cache-control": "no-store, no-cache, must-revalidate, max-age=0",
          "pragma": "no-cache",
          "expires": "0",
        },
      });
    }

    const googleEnrollment = path.match(/^\/api\/wallet\/google\/([^/]+)$/);
    if (req.method === "GET" && googleEnrollment) {
      const serial = safeId(googleEnrollment[1]);
      const row = await customer(serial);
      if (!row) return response({ message: "Cliente no encontrado" }, 404);
      const requestedCardId = url.searchParams.get("card")
        ? safeId(url.searchParams.get("card")!)
        : null;
      const cardRow = await loyaltyCard(row.business_id, requestedCardId);
      if (requestedCardId && !cardRow) {
        return response({ message: "Tarjeta no encontrada" }, 404);
      }
      await syncGooglePassDesign(row, cardRow)
        .catch((error) => console.error("Google Wallet design sync failed", error));
      const saveUrl = await googleSaveUrl(row, cardRow);
      if (!saveUrl) {
        return response({
          demoMode: true,
          message: "Modo demo: configura Issuer ID y Service Account para crear el enlace de Google Wallet.",
        }, 503);
      }
      return new Response(null, {
        status: 302,
        headers: { ...cors, location: saveUrl, "cache-control": "no-store" },
      });
    }

    const registration = path.match(/^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)\/([^/]+)$/);
    if (registration) {
      const device = safeId(registration[1]);
      const type = decodeURIComponent(registration[2]);
      const serial = safeId(registration[3]);
      if (type !== passTypeId || !(await appleAuthorized(req, serial))) return response({ message: "No autorizado" }, 401);
      if (req.method === "POST") {
        const { pushToken } = await req.json();
        if (!pushToken) return response({ message: "pushToken requerido" }, 400);
        const { data: previous } = await admin.from("wallet_registrations").select("serial_number").eq("device_library_identifier", device).eq("serial_number", serial).maybeSingle();
        const { data: supersededDevices } = await admin
          .from("wallet_devices")
          .select("device_library_identifier")
          .eq("push_token", String(pushToken))
          .neq("device_library_identifier", device);
        await admin.from("wallet_devices").upsert({ device_library_identifier: device, push_token: String(pushToken), updated_at: new Date().toISOString() });
        const supersededIds = (supersededDevices || []).map((item) => item.device_library_identifier as string);
        if (supersededIds.length) {
          const { data: oldRegistrations } = await admin
            .from("wallet_registrations")
            .select("serial_number,pass_type_identifier")
            .in("device_library_identifier", supersededIds);
          if (oldRegistrations?.length) {
            await admin.from("wallet_registrations").upsert(
              oldRegistrations.map((item) => ({
                device_library_identifier: device,
                serial_number: item.serial_number,
                pass_type_identifier: item.pass_type_identifier,
              })),
            );
          }
          await admin.from("wallet_devices").delete().in("device_library_identifier", supersededIds);
        }
        await admin.from("wallet_registrations").upsert({ device_library_identifier: device, serial_number: serial, pass_type_identifier: type });
        if (!previous) {
          const context = await passContext(serial);
          const welcomeTemplate = context?.cardRow?.welcome_message?.trim() || "";
          const welcomeMessage = context
            ? welcomeTemplate.replaceAll("{nombre}", context.customerRow.name)
            : "";
          // Claim the welcome atomically on the pass itself. Apple may register
          // the same pass twice almost simultaneously; checking registrations
          // before an upsert is not enough to prevent both requests from
          // sending the welcome notification.
          const claimedAt = new Date().toISOString();
          const { data: welcomeClaim } = await admin
            .from("wallet_passes")
            .update({ welcome_sent_at: claimedAt })
            .eq("serial_number", serial)
            .is("welcome_sent_at", null)
            .select("serial_number")
            .maybeSingle();
          if (context && welcomeMessage && welcomeClaim) {
            const updatedAt = new Date().toISOString();
            await Promise.all([
              admin
                .from("customers")
                .update({
                  wallet_message: walletNotificationValue(welcomeMessage),
                  updated_at: updatedAt,
                })
                .eq("business_id", context.customerRow.business_id)
                .eq("id", context.customerRow.id),
              admin
                .from("wallet_passes")
                .update({ update_tag: Date.now(), updated_at: updatedAt })
                .eq("serial_number", serial),
            ]);
            notifyPassesInBackground([serial]);
          }
        }
        return new Response(null, { status: previous ? 200 : 201 });
      }
      if (req.method === "DELETE") {
        await admin.from("wallet_registrations").delete().eq("device_library_identifier", device).eq("serial_number", serial).eq("pass_type_identifier", type);
        const { count } = await admin
          .from("wallet_registrations")
          .select("*", { count: "exact", head: true })
          .eq("device_library_identifier", device);
        if (!count) {
          await admin.from("wallet_devices").delete().eq("device_library_identifier", device);
        }
        return new Response(null, { status: 200 });
      }
    }

    const updates = path.match(/^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)$/);
    if (req.method === "GET" && updates) {
      const device = safeId(updates[1]);
      const type = decodeURIComponent(updates[2]);
      const since = Number(url.searchParams.get("passesUpdatedSince") || 0);
      const { data } = await admin.from("wallet_registrations").select("serial_number,wallet_passes!inner(update_tag)").eq("device_library_identifier", device).eq("pass_type_identifier", type);
      const changed = (data || []).filter((item) => Number((item.wallet_passes as unknown as { update_tag: number }).update_tag) > since);
      if (!changed.length) return new Response(null, { status: 204 });
      const lastUpdated = Math.max(...changed.map((item) => Number((item.wallet_passes as unknown as { update_tag: number }).update_tag)));
      return response({ serialNumbers: changed.map((item) => item.serial_number), lastUpdated: String(lastUpdated) });
    }

    const updatedPass = path.match(/^\/v1\/passes\/([^/]+)\/([^/]+)$/);
    if ((req.method === "GET" || req.method === "POST") && updatedPass) {
      const type = decodeURIComponent(updatedPass[1]);
      const serial = safeId(updatedPass[2]);
      if (type !== passTypeId || !(await appleAuthorized(req, serial))) return response({ message: "No autorizado" }, 401);
      if (req.method === "POST") return response(await notifyPass(serial));
      const context = await passContext(serial);
      if (!context) return response({ message: "Cliente no encontrado" }, 404);
      const bytes = await createPass(context.customerRow, serial, context.cardRow);
      const revision = String(context.walletPass?.update_tag || Date.now());
      const modifiedAt = context.walletPass?.updated_at
        ? new Date(context.walletPass.updated_at).toUTCString()
        : new Date().toUTCString();
      return new Response(bytes, {
        status: 200,
        headers: {
          ...cors,
          "content-type": "application/vnd.apple.pkpass",
          "cache-control": "no-store, no-cache, must-revalidate, max-age=0",
          "content-disposition": `attachment; filename="${serial}.pkpass"`,
          "last-modified": modifiedAt,
          "etag": `"fideli-${revision}"`,
          "x-fideli-pass-revision": revision,
        },
      });
    }

    if (req.method === "POST" && path === "/v1/log") return new Response(null, { status: 200 });
    return response({ message: "Ruta no encontrada" }, 404);
  } catch (error) {
    console.error(error);
    return response({ message: "No se pudo completar la operación" }, 500);
  }
});

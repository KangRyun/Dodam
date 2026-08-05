const C = {
  yellow50: "#FFF9DD",
  yellow100: "#FAEDAD",
  yellow500: "#F2D765",
  yellow600: "#E4C54F",
  yellow700: "#B39424",
  ink: "#2F2D24",
  inkMuted: "#696556",
  canvas: "#FFFDF5",
  canvasWarm: "#FFF7D6",
  surface: "#FFFFFF",
  surfaceSoft: "#FFFBEA",
  border: "#E8E1C9",
  borderStrong: "#CFC5A2",
  coral: "#FF806F",
  coralSoft: "#FFE4DF",
  mint: "#61CDB6",
  mintSoft: "#DDF7F0",
  sky: "#69BFE8",
  skySoft: "#E1F4FC",
  purple: "#9B87E8",
  purpleSoft: "#EEE9FF",
  green: "#3A966E",
  greenSoft: "#DCF1E7",
  amber: "#B77A12",
  amberSoft: "#FFF0C7",
  red: "#C95555",
  redSoft: "#FBE1E1",
  disabled: "#E4E0D4",
  onDisabled: "#9B978C",
  drawingRed: "#F06464",
  drawingBlue: "#4D9EE8",
  drawingGreen: "#55B875",
  drawingYellow: "#F2D765",
  drawingPurple: "#9666D6",
  drawingInk: "#3B3B3B",
  v2Sun: "#FFF5C2",
  v2Coral: "#FF806B",
  v2Aqua: "#4FC9C2",
  v2Sky: "#73C6F2",
  v2Purple: "#8C75DE",
  v2Leaf: "#7BCB6B",
  v2Shadow: "#C9AD42",
  v2Orange: "#FFB547",
  v2Cream: "#FFF9E8",
};

const GENERATED_PAGES = ["Dodam Child UI v2 · All Screens"];
const V2_REFERENCE_MODE = "vivid-character-sketchbook";
const LEGACY_GENERATED_PAGES = [
  "Dodam Child UI · All Screens",
  "00 · Dodam Child · Cover",
  "01 · Dodam Child · Foundations",
  "02 · Dodam Child · Components",
  "10 · Dodam Child · Mobile",
  "11 · Dodam Child · Tablet",
  "99 · Dodam Child · Handoff",
];
const GENERATED_NODE_KEY = "dodam-child-ui-generator";

const MOBILE_SCREENS = [
  ["C01", "Child Entry", "entry"],
  ["C02", "Profile Select", "profile"],
  ["C03", "Child Home", "home"],
  ["C04", "Activity Select", "mode"],
  ["C05", "Drawing Tutorial", "tutorial"],
  ["C06", "Drawing + Dialogue", "drawing"],
  ["C07", "Upload / Camera", "upload"],
  ["C08", "Upload Confirm", "confirm"],
  ["C09", "Uploaded Drawing Dialogue", "uploadDialogue"],
  ["C10", "Emotion Select", "emotion"],
  ["C11", "Completion + Praise", "complete"],
  ["C12", "History", "history"],
  ["C13", "Help", "help"],
  ["C14", "Exit Guardian Gate", "exit"],
];

const TABLET_SCREENS = MOBILE_SCREENS.slice(2);

let FONTS = {};
let IMAGES = {};

function rgb(hex) {
  const value = hex.replace("#", "");
  return {
    r: parseInt(value.slice(0, 2), 16) / 255,
    g: parseInt(value.slice(2, 4), 16) / 255,
    b: parseInt(value.slice(4, 6), 16) / 255,
  };
}

/** @returns {SolidPaint} */
function solid(hex, opacity = 1) {
  return { type: "SOLID", color: rgb(hex), opacity };
}

function base64Bytes(base64) {
  const alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const clean = base64.replace(/=+$/, "");
  const output = new Uint8Array(Math.floor((clean.length * 3) / 4));
  let buffer = 0;
  let bits = 0;
  let index = 0;

  for (let i = 0; i < clean.length; i += 1) {
    buffer = (buffer << 6) | alphabet.indexOf(clean[i]);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output[index] = (buffer >> bits) & 0xff;
      index += 1;
    }
  }

  return output.slice(0, index);
}

function normalizeFont(value) {
  return value.toLowerCase().replace(/[\s_-]/g, "");
}

async function loadFonts() {
  const available = await figma.listAvailableFontsAsync();
  const nanum = available.filter(({ fontName }) =>
    normalizeFont(fontName.family).includes("nanumsquareneo"),
  );

  const interRegular = { family: "Inter", style: "Regular" };
  const interBold = { family: "Inter", style: "Bold" };
  const signature = ({ fontName }) =>
    normalizeFont(`${fontName.family}${fontName.style}`);
  const find = (predicate, fallback) => {
    const match = nanum.find((item) => predicate(signature(item)));
    return match ? match.fontName : fallback;
  };

  FONTS = {
    regular: find(
      (value) =>
        (value.includes("regular") || value.endsWith("rg")) &&
        !value.includes("bold") &&
        !value.includes("heavy"),
      interRegular,
    ),
    bold: find(
      (value) =>
        (value.includes("bold") || value.endsWith("bd")) &&
        !value.includes("extrabold") &&
        !value.includes("heavy"),
      interBold,
    ),
    extraBold: find(
      (value) =>
        value.includes("heavy") ||
        value.includes("extrabold") ||
        value.endsWith("hv") ||
        value.endsWith("eb"),
      interBold,
    ),
  };

  await Promise.all(
    Object.values(FONTS).map((font) => figma.loadFontAsync(font)),
  );

  return {
    detected: nanum.map(({ fontName }) => fontName),
    usingFallback: !Object.values(FONTS).some((font) =>
      normalizeFont(font.family).includes("nanumsquareneo"),
    ),
  };
}

function makeFrame(name, width, height, fill = C.canvas) {
  const frame = figma.createFrame();
  frame.name = name;
  frame.resize(width, height);
  frame.fills = [solid(fill)];
  frame.clipsContent = true;
  return frame;
}

/**
 * @param {string} name
 * @param {'VERTICAL' | 'HORIZONTAL' | 'GRID' | 'NONE'} direction
 * @param {number} gap
 */
function makeAutoFrame(name, direction = "VERTICAL", gap = 0) {
  const frame = figma.createFrame();
  frame.name = name;
  frame.layoutMode = direction;
  frame.primaryAxisSizingMode = "AUTO";
  frame.counterAxisSizingMode = "AUTO";
  frame.itemSpacing = gap;
  frame.fills = [];
  frame.clipsContent = false;
  return frame;
}

function rounded(parent, name, x, y, width, height, fill, radius = 20, stroke) {
  const node = figma.createRectangle();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(width, height);
  node.cornerRadius = radius;
  node.fills = [solid(fill)];
  if (stroke) {
    node.strokes = [solid(stroke)];
    node.strokeWeight = 1;
  }
  parent.appendChild(node);
  return node;
}

function circle(parent, name, x, y, size, fill, stroke) {
  const node = figma.createEllipse();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(size, size);
  node.fills = [solid(fill)];
  if (stroke) {
    node.strokes = [solid(stroke)];
    node.strokeWeight = 1;
  }
  parent.appendChild(node);
  return node;
}

/**
 * @param {BaseNode & ChildrenMixin} parent
 * @param {string} characters
 * @param {number} x
 * @param {number} y
 * @param {number} width
 * @param {number} size
 * @param {'regular' | 'bold' | 'extraBold'} weight
 * @param {string} color
 * @param {'LEFT' | 'CENTER' | 'RIGHT' | 'JUSTIFIED'} align
 * @param {number=} lineHeight
 */
function makeText(
  parent,
  characters,
  x,
  y,
  width,
  size = 16,
  weight = "regular",
  color = C.ink,
  align = "LEFT",
  lineHeight,
) {
  const node = figma.createText();
  node.fontName = FONTS[weight];
  node.characters = characters;
  node.fontSize = size;
  node.lineHeight = { unit: "PIXELS", value: lineHeight || Math.round(size * 1.45) };
  node.fills = [solid(color)];
  node.textAlignHorizontal = align;
  node.textAutoResize = "HEIGHT";
  node.resize(width, Math.max(24, lineHeight || Math.round(size * 1.45)));
  node.x = x;
  node.y = y;
  parent.appendChild(node);
  return node;
}

function addShadow(node, y = 4, blur = 14, opacity = 0.1) {
  node.effects = [
    {
      type: "DROP_SHADOW",
      color: { ...rgb(C.ink), a: opacity },
      offset: { x: 0, y },
      radius: blur,
      spread: 0,
      visible: true,
      blendMode: "NORMAL",
    },
  ];
}

/**
 * @param {BaseNode & ChildrenMixin} parent
 * @param {string} name
 * @param {string} hash
 * @param {number} x
 * @param {number} y
 * @param {number} width
 * @param {number} height
 * @param {'FIT' | 'FILL' | 'CROP' | 'TILE'} scaleMode
 */
function imageRect(parent, name, hash, x, y, width, height, scaleMode = "FILL") {
  const node = figma.createRectangle();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(width, height);
  node.fills = [{ type: "IMAGE", imageHash: hash, scaleMode }];
  parent.appendChild(node);
  return node;
}

function iconSvg(kind, color = C.ink) {
  const paths = {
    home: '<path d="M4 11.2 12 4l8 7.2V20h-5v-5H9v5H4z" fill="none" stroke="COLOR" stroke-width="2" stroke-linejoin="round"/>',
    draw: '<path d="m5 19 2.2-6.3L16.7 3.2a1.7 1.7 0 0 1 2.4 0l1.7 1.7a1.7 1.7 0 0 1 0 2.4l-9.5 9.5z" fill="none" stroke="COLOR" stroke-width="2" stroke-linejoin="round"/><path d="m14.8 5.2 4 4" stroke="COLOR" stroke-width="2"/>',
    camera: '<rect x="3" y="7" width="18" height="13" rx="3" fill="none" stroke="COLOR" stroke-width="2"/><path d="m8 7 1.5-3h5L16 7" fill="none" stroke="COLOR" stroke-width="2"/><circle cx="12" cy="13.5" r="3.2" fill="none" stroke="COLOR" stroke-width="2"/>',
    history: '<path d="M4 6v5h5" fill="none" stroke="COLOR" stroke-width="2" stroke-linecap="round"/><path d="M5.2 10A7.5 7.5 0 1 1 6 17.8" fill="none" stroke="COLOR" stroke-width="2" stroke-linecap="round"/><path d="M12 8v5l3 2" fill="none" stroke="COLOR" stroke-width="2" stroke-linecap="round"/>',
    help: '<circle cx="12" cy="12" r="9" fill="none" stroke="COLOR" stroke-width="2"/><path d="M9.7 9a2.4 2.4 0 1 1 3.5 2.2c-.8.4-1.2.9-1.2 1.8" fill="none" stroke="COLOR" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17" r="1" fill="COLOR"/>',
    back: '<path d="m15 5-7 7 7 7" fill="none" stroke="COLOR" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
    check: '<path d="m5 12.5 4.3 4.3L19 7" fill="none" stroke="COLOR" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>',
    mic: '<rect x="8" y="3" width="8" height="12" rx="4" fill="none" stroke="COLOR" stroke-width="2"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3" fill="none" stroke="COLOR" stroke-width="2" stroke-linecap="round"/>',
    close: '<path d="m6 6 12 12M18 6 6 18" stroke="COLOR" stroke-width="2.4" stroke-linecap="round"/>',
    upload: '<path d="M12 16V4m0 0L7 9m5-5 5 5M5 15v4h14v-4" fill="none" stroke="COLOR" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  };
  return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${(paths[kind] || paths.help).replaceAll("COLOR", color)}</svg>`;
}

function addIcon(parent, kind, x, y, size = 24, color = C.ink) {
  const node = figma.createNodeFromSvg(iconSvg(kind, color));
  node.name = `Icon / ${kind}`;
  node.x = x;
  node.y = y;
  node.resize(size, size);
  parent.appendChild(node);
  return node;
}

function addHeader(screen, title, section, showBack = true) {
  if (showBack) {
    rounded(screen, "Back button", 20, 44, 48, 48, C.surface, 16, C.border);
    addIcon(screen, "back", 32, 56, 24);
  }
  makeText(screen, section, showBack ? 84 : 24, 47, 220, 13, "bold", C.inkMuted);
  makeText(screen, title, showBack ? 84 : 24, 65, 270, 22, "extraBold", C.ink);
  rounded(screen, "Help button", screen.width - 68, 44, 48, 48, C.surface, 16, C.border);
  addIcon(screen, "help", screen.width - 56, 56, 24);
}

function addPrimaryButton(parent, label, x, y, width, icon) {
  const button = rounded(parent, `Button / ${label}`, x, y, width, 60, C.yellow500, 20);
  if (icon) {
    addIcon(parent, icon, x + 18, y + 18, 24);
    makeText(parent, label, x + 50, y + 17, width - 68, 17, "bold");
  } else {
    makeText(parent, label, x + 12, y + 17, width - 24, 17, "bold", C.ink, "CENTER");
  }
  return button;
}

function addSecondaryButton(parent, label, x, y, width) {
  const button = rounded(parent, `Button / ${label}`, x, y, width, 56, C.surface, 18, C.borderStrong);
  makeText(parent, label, x + 12, y + 15, width - 24, 16, "bold", C.ink, "CENTER");
  return button;
}

function addActivityCard(parent, title, description, icon, color, x, y, width, height) {
  const card = rounded(parent, `Activity Card / ${title}`, x, y, width, height, color, 24);
  addShadow(card, 4, 14, 0.08);
  circle(parent, `${title} icon background`, x + 20, y + 20, 52, C.surface);
  addIcon(parent, icon, x + 34, y + 34, 24);
  makeText(parent, title, x + 20, y + 88, width - 40, 20, "extraBold");
  makeText(parent, description, x + 20, y + 122, width - 40, 14, "regular", C.inkMuted);
  return card;
}

function addTactileTile(parent, name, x, y, width, height, color, label, iconKind) {
  rounded(parent, `${name} / shadow`, x, y + 8, width, height, C.v2Shadow, 34);
  const tile = rounded(parent, name, x, y, width, height, color, 34);
  addShadow(tile, 3, 10, 0.08);
  circle(parent, `${name} / icon plate`, x + 20, y + 18, Math.min(72, height * 0.38), C.surface);
  addIcon(parent, iconKind, x + 39, y + 37, Math.min(34, height * 0.18), C.ink);
  makeText(parent, label, x + 20, y + height - 58, width - 40, width > 220 ? 22 : 18, "extraBold");
  return tile;
}

function addSceneBackdrop(parent, width, height, primaryColor = C.v2Sun, secondaryColor = C.v2Sky) {
  rounded(parent, "V2 scene background", 0, 0, width, height, primaryColor, 0);
  circle(parent, "V2 sun glow", width - 112, 44, 72, C.yellow500);
  circle(parent, "V2 cloud 1", -34, 118, 130, C.surface);
  circle(parent, "V2 cloud 2", 34, 100, 108, C.surface);
  circle(parent, "V2 cloud 3", width * 0.56, 152, 92, C.surface);
  circle(parent, "V2 cloud 4", width * 0.62, 132, 118, C.surface);
  const hillY = height * 0.72;
  circle(parent, "V2 hill back", -width * 0.12, hillY, width * 0.82, secondaryColor);
  circle(parent, "V2 hill front", width * 0.42, hillY - 20, width * 0.84, C.v2Leaf);
  [0.14, 0.32, 0.76].forEach((ratio, index) =>
    circle(parent, `V2 floating dot ${index + 1}`, width * ratio, 72 + index * 46, 14 + index * 4, index === 1 ? C.v2Coral : C.yellow500),
  );
}

function addCrayonTray(parent, x, y, width, compact = false) {
  const trayHeight = compact ? 76 : 96;
  rounded(parent, "Crayon tray shadow", x, y + 7, width, trayHeight, "#D7B981", 24);
  rounded(parent, "Crayon tray", x, y, width, trayHeight, "#F6D9A0", 24, "#B78550");
  const colors = [
    C.drawingRed,
    C.v2Orange,
    C.drawingYellow,
    C.drawingGreen,
    C.drawingBlue,
    C.drawingPurple,
    C.drawingInk,
    C.surface,
  ];
  const gap = (width - 34) / colors.length;
  colors.forEach((color, index) => {
    const crayon = rounded(
      parent,
      `Crayon / ${index + 1}`,
      x + 17 + index * gap,
      y + (compact ? 17 : 19),
      Math.min(26, gap - 6),
      compact ? 43 : 58,
      color,
      8,
      index === 2 ? C.ink : "#A97748",
    );
    crayon.rotation = index % 2 === 0 ? -3 : 3;
  });
}

function addStickerBurst(parent, x, y, color, scale = 1) {
  const sizes = [18, 10, 14, 8];
  sizes.forEach((size, index) => {
    circle(
      parent,
      `Celebration dot ${index + 1}`,
      x + index * 38 * scale,
      y + (index % 2) * 24 * scale,
      size * scale,
      index % 2 === 0 ? color : C.v2Sky,
    );
  });
  makeText(parent, "★", x + 26 * scale, y - 24 * scale, 44 * scale, 30 * scale, "extraBold", C.yellow500, "CENTER");
}

function addDodamiBubble(parent, textValue, x, y, width, imageKind = "brand") {
  const hash = imageKind === "drawing" ? IMAGES.drawing : IMAGES.brand;
  rounded(parent, "Dodami guide", x, y, width, 128, C.surface, 24, C.border);
  imageRect(parent, `Dodami / ${imageKind}`, hash, x + 12, y + 10, 104, 104);
  rounded(parent, "Speech bubble", x + 116, y + 18, width - 132, 88, C.yellow50, 18);
  makeText(parent, textValue, x + 132, y + 36, width - 164, 16, "bold", C.ink);
}

function addDoodle(parent, x, y, width, height) {
  rounded(parent, "Drawing paper", x, y, width, height, C.surface, 24, C.border);
  const sky = figma.createEllipse();
  sky.name = "Drawing / sun";
  sky.resize(44, 44);
  sky.x = x + width - 82;
  sky.y = y + 34;
  sky.fills = [solid(C.drawingYellow)];
  parent.appendChild(sky);

  for (let i = 0; i < 4; i += 1) {
    const tree = rounded(
      parent,
      `Drawing / tree ${i + 1}`,
      x + 42 + i * 54,
      y + 110 + (i % 2) * 15,
      34,
      80,
      C.drawingGreen,
      16,
    );
    tree.rotation = i % 2 === 0 ? -4 : 5;
    rounded(parent, "Drawing / trunk", x + 54 + i * 54, y + 170, 10, 48, "#9E6A43", 5);
  }

  const path = figma.createVector();
  path.name = "Drawing / ground";
  path.x = x + 30;
  path.y = y + height - 110;
  path.vectorPaths = [
    {
      windingRule: "NONE",
      data: `M 0 46 C ${width * 0.3 - 30} 0 ${width * 0.65 - 30} 82 ${width - 60} 40`,
    },
  ];
  path.strokes = [solid(C.drawingGreen)];
  path.strokeWeight = 6;
  path.strokeCap = "ROUND";
  parent.appendChild(path);
}

function addEmotionFace(parent, label, x, y, color, selected = false, size = 60) {
  circle(parent, `Emotion / ${label}`, x, y, size, color, selected ? C.ink : C.border);
  circle(parent, `${label} eye left`, x + size * 0.28, y + size * 0.32, size * 0.1, C.ink);
  circle(parent, `${label} eye right`, x + size * 0.62, y + size * 0.32, size * 0.1, C.ink);
  const mouth = figma.createLine();
  mouth.name = `${label} mouth`;
  mouth.x = x + size * 0.34;
  mouth.y = y + size * 0.68;
  mouth.resize(size * 0.3, 0);
  mouth.strokes = [solid(C.ink)];
  mouth.strokeWeight = 2.5;
  mouth.strokeCap = "ROUND";
  parent.appendChild(mouth);
  makeText(parent, label, x - 10, y + size + 8, size + 20, 13, "bold", C.ink, "CENTER");
}

async function ensureVariables() {
  if (!figma.variables) return;

  const existingCollections = await figma.variables.getLocalVariableCollectionsAsync();
  const getCollection = (name, modeName) => {
    let collection = existingCollections.find((item) => item.name === name);
    if (!collection) collection = figma.variables.createVariableCollection(name);
    collection.renameMode(collection.modes[0].modeId, modeName);
    return collection;
  };

  const primitive = getCollection("Dodam · Primitive", "Value");
  const semantic = getCollection("Dodam · Semantic", "Child");
  const dimension = getCollection("Dodam · Dimension", "Default");
  const existingVariables = await figma.variables.getLocalVariablesAsync();

  const setVariable = (collection, name, type, value, scopes = []) => {
    let variable = existingVariables.find(
      (item) => item.variableCollectionId === collection.id && item.name === name,
    );
    if (!variable) variable = figma.variables.createVariable(name, collection, type);
    variable.setValueForMode(collection.modes[0].modeId, value);
    if (scopes.length) {
      try {
        variable.scopes = scopes;
      } catch (_) {
        // Scope support differs between Figma plans; values remain usable.
      }
    }
    return variable;
  };

  const primitiveMap = {
    "yellow/50": C.yellow50,
    "yellow/100": C.yellow100,
    "yellow/500": C.yellow500,
    "yellow/600": C.yellow600,
    "yellow/700": C.yellow700,
    "neutral/ink": C.ink,
    "neutral/ink-muted": C.inkMuted,
    "neutral/canvas": C.canvas,
    "neutral/canvas-warm": C.canvasWarm,
    "neutral/surface": C.surface,
    "neutral/surface-soft": C.surfaceSoft,
    "neutral/border": C.border,
    "neutral/border-strong": C.borderStrong,
    "support/coral": C.coral,
    "support/mint": C.mint,
    "support/sky": C.sky,
    "support/purple": C.purple,
    "status/success": C.green,
    "status/warning": C.amber,
    "status/error": C.red,
  };

  const primitiveVariables = {};
  Object.entries(primitiveMap).forEach(([name, value]) => {
    primitiveVariables[name] = setVariable(
      primitive,
      name,
      "COLOR",
      rgb(value),
      ["ALL_FILLS", "STROKE_COLOR"],
    );
  });

  const aliasMap = {
    "background/canvas": "neutral/canvas",
    "background/warm": "neutral/canvas-warm",
    "surface/default": "neutral/surface",
    "surface/subtle": "neutral/surface-soft",
    "action/primary": "yellow/500",
    "action/primary-hover": "yellow/600",
    "action/primary-pressed": "yellow/700",
    "text/primary": "neutral/ink",
    "text/secondary": "neutral/ink-muted",
    "border/default": "neutral/border",
    "border/strong": "neutral/border-strong",
    "feedback/success": "status/success",
    "feedback/warning": "status/warning",
    "feedback/error": "status/error",
  };

  Object.entries(aliasMap).forEach(([name, source]) => {
    setVariable(
      semantic,
      name,
      "COLOR",
      figma.variables.createVariableAlias(primitiveVariables[source]),
      ["ALL_FILLS", "STROKE_COLOR"],
    );
  });

  const dimensions = {
    "space/4": 4,
    "space/8": 8,
    "space/12": 12,
    "space/16": 16,
    "space/20": 20,
    "space/24": 24,
    "space/32": 32,
    "space/40": 40,
    "space/48": 48,
    "radius/12": 12,
    "radius/16": 16,
    "radius/20": 20,
    "radius/24": 24,
    "radius/full": 999,
    "touch/minimum": 48,
    "touch/standard": 56,
    "touch/child": 64,
  };

  Object.entries(dimensions).forEach(([name, value]) =>
    setVariable(dimension, name, "FLOAT", value),
  );
}

async function ensureTextStyles() {
  /** @type {Array<[string, number, number, 'regular' | 'bold' | 'extraBold']>} */
  const definitions = [
    ["Dodam/Display/Large", 32, 40, "extraBold"],
    ["Dodam/Title/Large", 26, 34, "extraBold"],
    ["Dodam/Title/Medium", 22, 30, "bold"],
    ["Dodam/Body/Large", 18, 28, "regular"],
    ["Dodam/Body/Medium", 16, 24, "regular"],
    ["Dodam/Body/Small", 14, 21, "regular"],
    ["Dodam/Label/Large", 16, 22, "bold"],
    ["Dodam/Label/Small", 13, 18, "bold"],
  ];

  const existing = await figma.getLocalTextStylesAsync();
  definitions.forEach(([name, size, lineHeight, weight]) => {
    let style = existing.find((item) => item.name === name);
    if (!style) style = figma.createTextStyle();
    style.name = name;
    style.fontName = FONTS[weight];
    style.fontSize = size;
    style.lineHeight = { unit: "PIXELS", value: lineHeight };
    style.description = "Dodam child-only typography · NanumSquare Neo";
  });
}

function createCoverPage(page) {
  const cover = makeFrame("Dodam Child UI v1 · Cover", 1440, 1024, C.yellow500);
  page.appendChild(cover);
  rounded(cover, "White canvas", 80, 80, 1280, 864, C.surface, 40);
  imageRect(cover, "Dodami brand", IMAGES.brand, 830, 160, 430, 430);
  makeText(cover, "도담", 160, 166, 500, 72, "extraBold", C.ink);
  makeText(cover, "아이의 그림과 마음을\n다정하게 이어주는 시간", 160, 276, 590, 42, "extraBold", C.ink, "LEFT", 56);
  makeText(
    cover,
    "Child UI Design System · Mobile 390 × 844 · Tablet 1194 × 834",
    160,
    426,
    620,
    18,
    "regular",
    C.inkMuted,
  );
  rounded(cover, "Scope chip", 160, 516, 230, 48, C.yellow50, 24);
  makeText(cover, "아동 화면 전용", 180, 528, 190, 16, "bold", C.ink, "CENTER");
  makeText(cover, "Primary  #F2D765", 160, 632, 300, 18, "bold");
  makeText(cover, "NanumSquare Neo", 160, 674, 300, 18, "bold");
  makeText(cover, "Dodami yellow scarf edition", 160, 716, 420, 18, "bold");
  makeText(cover, "v1 · 2026.07.27", 160, 848, 300, 14, "regular", C.inkMuted);
}

function createFoundationsPage(page) {
  const board = makeFrame("Foundations", 1800, 1500, C.canvas);
  page.appendChild(board);
  makeText(board, "01 · Foundations", 72, 64, 800, 40, "extraBold");
  makeText(board, "따뜻한 노랑, 선명한 보조색, 큼직한 터치 영역", 72, 118, 900, 18, "regular", C.inkMuted);

  const swatches = [
    ["Yellow 500", C.yellow500],
    ["Ink", C.ink],
    ["Canvas", C.canvas],
    ["Coral", C.coral],
    ["Mint", C.mint],
    ["Sky", C.sky],
    ["Purple", C.purple],
    ["Success", C.green],
  ];
  swatches.forEach(([name, color], index) => {
    const x = 72 + (index % 4) * 300;
    const y = 210 + Math.floor(index / 4) * 210;
    rounded(board, `Swatch / ${name}`, x, y, 260, 142, color, 24, color === C.canvas ? C.border : undefined);
    makeText(board, name, x, y + 154, 200, 16, "bold");
    makeText(board, color, x, y + 180, 200, 13, "regular", C.inkMuted);
  });

  makeText(board, "Typography", 72, 664, 600, 28, "extraBold");
  makeText(board, "아이의 말이 가장 먼저 보여요", 72, 724, 920, 32, "extraBold");
  makeText(board, "무슨 색으로 그리고 싶어?", 72, 790, 720, 26, "extraBold");
  makeText(board, "도다미가 옆에서 천천히 기다릴게.", 72, 850, 720, 18, "regular");
  makeText(board, "NanumSquare Neo · 짧고 쉬운 문장 · 줄 간격 140% 이상", 72, 898, 900, 14, "regular", C.inkMuted);

  makeText(board, "Spacing & radius", 72, 1010, 600, 28, "extraBold");
  [8, 12, 16, 20, 24, 32, 48].forEach((value, index) => {
    rounded(board, `${value}px token`, 72, 1070 + index * 48, value * 4, 24, C.yellow500, 8);
    makeText(board, `${value}px`, 300, 1069 + index * 48, 120, 14, "bold");
  });

  [12, 16, 20, 24].forEach((value, index) => {
    rounded(board, `Radius ${value}`, 650 + index * 230, 1070, 190, 120, C.surface, value, C.border);
    makeText(board, `Radius ${value}`, 670 + index * 230, 1118, 150, 14, "bold", C.ink, "CENTER");
  });

  imageRect(board, "Dodami approved asset", IMAGES.brand, 1300, 180, 370, 370);
  imageRect(board, "Dodami drawing asset", IMAGES.drawing, 1270, 620, 410, 410);
  makeText(board, "도다미 자산", 1320, 1060, 320, 26, "extraBold", C.ink, "CENTER");
  makeText(board, "스카프 #F2D765 고정\n48px 이하 축소 금지", 1320, 1110, 320, 16, "regular", C.inkMuted, "CENTER");
}

function createButtonComponent(label, type, state) {
  const component = figma.createComponent();
  component.name = `Type=${type}, State=${state}`;
  component.layoutMode = "HORIZONTAL";
  component.primaryAxisAlignItems = "CENTER";
  component.counterAxisAlignItems = "CENTER";
  component.paddingLeft = 24;
  component.paddingRight = 24;
  component.paddingTop = 17;
  component.paddingBottom = 17;
  component.itemSpacing = 10;
  component.cornerRadius = 20;
  component.resize(220, 60);
  component.primaryAxisSizingMode = "FIXED";
  component.counterAxisSizingMode = "FIXED";

  const isDisabled = state === "Disabled";
  const fill =
    isDisabled ? C.disabled : type === "Primary" ? C.yellow500 : C.surface;
  component.fills = [solid(fill)];
  if (type !== "Primary" && !isDisabled) component.strokes = [solid(C.borderStrong)];
  if (state === "Pressed" && !isDisabled) component.opacity = 0.76;

  const textNode = figma.createText();
  textNode.fontName = FONTS.bold;
  textNode.characters = label;
  textNode.fontSize = 16;
  textNode.fills = [solid(isDisabled ? C.onDisabled : C.ink)];
  component.appendChild(textNode);
  component.description = "Child touch target 60px · NanumSquare Neo Bold";
  return component;
}

function createActivityComponent(type, title, color, iconKind) {
  const component = figma.createComponent();
  component.name = `Type=${type}`;
  component.resize(260, 190);
  component.cornerRadius = 24;
  component.fills = [solid(color)];
  circle(component, "Icon background", 20, 20, 52, C.surface);
  addIcon(component, iconKind, 34, 34, 24);
  makeText(component, title, 20, 92, 220, 20, "extraBold");
  makeText(component, "하고 싶은 활동을 골라봐.", 20, 130, 220, 14, "regular", C.inkMuted);
  component.description = "Child home activity card";
  return component;
}

function createChipComponent(selected) {
  const component = figma.createComponent();
  component.name = `Selected=${selected ? "True" : "False"}`;
  component.layoutMode = "HORIZONTAL";
  component.primaryAxisAlignItems = "CENTER";
  component.counterAxisAlignItems = "CENTER";
  component.paddingLeft = 18;
  component.paddingRight = 18;
  component.paddingTop = 12;
  component.paddingBottom = 12;
  component.cornerRadius = 999;
  component.fills = [solid(selected ? C.yellow100 : C.surface)];
  component.strokes = [solid(selected ? C.yellow700 : C.border)];
  const label = figma.createText();
  label.fontName = FONTS.bold;
  label.characters = selected ? "선택했어요" : "골라보기";
  label.fontSize = 14;
  label.fills = [solid(C.ink)];
  component.appendChild(label);
  return component;
}

function createComponentsPage(page) {
  const board = makeFrame("Components", 2000, 1700, C.canvas);
  page.appendChild(board);
  makeText(board, "02 · Components", 72, 64, 800, 40, "extraBold");
  makeText(board, "모든 주요 행동은 56px 이상, 아동 핵심 행동은 64px에 가깝게", 72, 118, 1000, 18, "regular", C.inkMuted);

  makeText(board, "Action / Button", 72, 210, 500, 26, "extraBold");
  const buttonComponents = [];
  ["Primary", "Secondary"].forEach((type, typeIndex) => {
    ["Default", "Pressed", "Disabled"].forEach((state, stateIndex) => {
      const component = createButtonComponent("그림 그리기", type, state);
      component.x = 72 + stateIndex * 260;
      component.y = 270 + typeIndex * 110;
      board.appendChild(component);
      buttonComponents.push(component);
    });
  });
  const buttonSet = figma.combineAsVariants(buttonComponents, board);
  buttonSet.name = "Action / Button";
  buttonSet.description = "Primary and secondary child action states";

  makeText(board, "Activity / Card", 72, 580, 500, 26, "extraBold");
  const cardComponents = [
    createActivityComponent("Draw", "그림 그리기", C.coralSoft, "draw"),
    createActivityComponent("Upload", "사진 가져오기", C.skySoft, "camera"),
    createActivityComponent("History", "지난 활동", C.mintSoft, "history"),
  ];
  cardComponents.forEach((component, index) => {
    component.x = 72 + index * 300;
    component.y = 640;
    board.appendChild(component);
  });
  const cardSet = figma.combineAsVariants(cardComponents, board);
  cardSet.name = "Activity / Card";

  makeText(board, "Choice / Chip", 72, 920, 500, 26, "extraBold");
  const chipComponents = [createChipComponent(false), createChipComponent(true)];
  chipComponents.forEach((component, index) => {
    component.x = 72 + index * 180;
    component.y = 980;
    board.appendChild(component);
  });
  const chipSet = figma.combineAsVariants(chipComponents, board);
  chipSet.name = "Choice / Chip";

  makeText(board, "Emotion / Choice", 72, 1140, 500, 26, "extraBold");
  const emotionColors = [C.coralSoft, C.yellow100, C.mintSoft, C.skySoft, C.purpleSoft];
  const labels = ["신나요", "좋아요", "그냥 그래요", "속상해요", "화나요"];
  const emotionComponents = labels.map((label, index) => {
    const component = figma.createComponent();
    component.name = `Emotion=${label}`;
    component.resize(120, 132);
    component.cornerRadius = 20;
    component.fills = [solid(C.surface)];
    component.strokes = [solid(C.border)];
    addEmotionFace(component, label, 30, 16, emotionColors[index], index === 1, 60);
    component.x = 72 + index * 150;
    component.y = 1200;
    board.appendChild(component);
    return component;
  });
  const emotionSet = figma.combineAsVariants(emotionComponents, board);
  emotionSet.name = "Emotion / Choice";

  addDodamiBubble(board, "정답은 없어. 지금 마음을 골라줘.", 1050, 270, 760);
  addDodamiBubble(board, "다 그렸으면 나에게 알려줘!", 1050, 440, 760, "drawing");
  rounded(board, "Recorder panel", 1050, 640, 760, 220, C.surface, 28, C.border);
  circle(board, "Mic action", 1110, 710, 80, C.yellow500);
  addIcon(board, "mic", 1138, 738, 24);
  makeText(board, "도다미에게 말해줘", 1220, 700, 460, 24, "extraBold");
  makeText(board, "말하고 있는 동안 점이 움직여요.", 1220, 750, 460, 16, "regular", C.inkMuted);
  [0, 1, 2, 3, 4].forEach((index) =>
    circle(board, `Voice dot ${index + 1}`, 1220 + index * 28, 804, 12, index === 2 ? C.coral : C.yellow500),
  );
}

function createV2DirectionSection(page) {
  const board = makeFrame("Dodam Child UI v2 / Direction", 1600, 1100, C.v2Sun);
  page.appendChild(board);
  addSceneBackdrop(board, 1600, 1100, C.v2Sun, C.v2Sky);
  rounded(board, "V2 brand ribbon", 88, 76, 340, 54, C.surface, 27);
  makeText(board, "DODAM CHILD UI · V2", 112, 89, 292, 16, "extraBold", C.ink, "CENTER");
  makeText(board, "도다미와 만드는\n나만의 이야기", 92, 194, 700, 66, "extraBold", C.ink, "LEFT", 78);
  makeText(
    board,
    "선명한 놀이 타일 · 캐릭터가 이끄는 탐색 · 손에 잡히는 스케치북",
    96,
    378,
    720,
    22,
    "bold",
    C.inkMuted,
  );
  imageRect(board, "Dodami v2 hero", IMAGES.brand, 930, 126, 520, 520);
  const activities = [
    ["그림 그리기", C.v2Coral, "draw"],
    ["사진 가져오기", C.v2Sky, "camera"],
    ["도다미와 대화", C.v2Aqua, "mic"],
    ["마음 고르기", C.v2Purple, "check"],
  ];
  activities.forEach(([label, color, icon], index) => {
    addTactileTile(board, `V2 direction tile ${index + 1}`, 92 + index * 368, 716, 330, 220, color, label, icon);
  });
  makeText(board, `Reference mode: ${V2_REFERENCE_MODE}`, 96, 1018, 600, 14, "bold", C.inkMuted);
}

function createV2FoundationsSection(page) {
  const board = makeFrame("Dodam Child UI v2 / Foundations", 1900, 1600, C.v2Cream);
  page.appendChild(board);
  makeText(board, "01 · V2 Foundations", 72, 58, 900, 42, "extraBold");
  makeText(board, "흰 카드 대신 색·장면·촉감으로 먼저 이해하는 아동 UI", 72, 116, 980, 20, "bold", C.inkMuted);
  const swatches = [
    ["SUN", C.v2Sun],
    ["YELLOW", C.yellow500],
    ["CORAL", C.v2Coral],
    ["AQUA", C.v2Aqua],
    ["SKY", C.v2Sky],
    ["PURPLE", C.v2Purple],
    ["LEAF", C.v2Leaf],
  ];
  swatches.forEach(([label, color], index) => {
    rounded(board, `V2 swatch ${label}`, 72 + index * 246, 202, 210, 152, color, 30, color === C.v2Sun ? C.borderStrong : undefined);
    makeText(board, label, 88 + index * 246, 374, 178, 14, "extraBold", C.ink, "CENTER");
    makeText(board, color, 88 + index * 246, 400, 178, 13, "regular", C.inkMuted, "CENTER");
  });
  makeText(board, "NanumSquare Neo", 72, 500, 800, 50, "extraBold");
  makeText(board, "오늘은 무엇을 그려볼까?", 72, 580, 820, 32, "extraBold");
  makeText(board, "도다미가 옆에서 천천히 기다릴게.", 72, 644, 820, 21, "bold", C.inkMuted);
  addTactileTile(board, "Foundation tactile tile", 1030, 486, 360, 238, C.v2Coral, "그림 그리기", "draw");
  addTactileTile(board, "Foundation tactile tile 2", 1420, 486, 360, 238, C.v2Aqua, "이야기하기", "mic");
  makeText(board, "Sketchbook & crayons", 72, 790, 800, 34, "extraBold");
  rounded(board, "V2 paper shadow", 72, 858, 980, 560, "#D8C89B", 34);
  rounded(board, "V2 paper sheet", 60, 844, 980, 560, C.surface, 34, "#C8B179");
  rounded(board, "Paper tape left", 94, 824, 146, 34, C.yellow100, 6);
  rounded(board, "Paper tape right", 856, 824, 146, 34, C.yellow100, 6);
  addDoodle(board, 106, 902, 888, 390);
  addCrayonTray(board, 1110, 904, 670, false);
  imageRect(board, "Approved Dodami drawing v2", IMAGES.drawing, 1190, 1070, 500, 430);
}

function createV2ComponentsSection(page) {
  const board = makeFrame("Dodam Child UI v2 / Components", 2100, 1800, C.canvas);
  page.appendChild(board);
  makeText(board, "02 · V2 Components", 72, 58, 900, 42, "extraBold");
  makeText(board, "큰 색면, 물체처럼 눌리는 깊이, 표정과 문장을 함께 제공", 72, 116, 1040, 20, "bold", C.inkMuted);

  makeText(board, "Activity Tile / V2", 72, 204, 600, 28, "extraBold");
  const activityComponents = [
    createActivityComponent("DrawV2", "그림 그리기", C.v2Coral, "draw"),
    createActivityComponent("PhotoV2", "사진 가져오기", C.v2Sky, "camera"),
    createActivityComponent("TalkV2", "도다미와 대화", C.v2Aqua, "mic"),
    createActivityComponent("HeartV2", "마음 고르기", C.v2Purple, "check"),
  ];
  activityComponents.forEach((component, index) => {
    component.resize(300, 220);
    component.cornerRadius = 34;
    component.x = 72 + index * 340;
    component.y = 264;
    board.appendChild(component);
  });
  const activitySet = figma.combineAsVariants(activityComponents, board);
  activitySet.name = "Activity Tile / V2";

  makeText(board, "Voice Button / V2", 72, 610, 600, 28, "extraBold");
  const voiceComponents = ["Ready", "Listening", "Complete"].map((state, index) => {
    const component = figma.createComponent();
    component.name = `State=${state}`;
    component.resize(220, 92);
    component.cornerRadius = 32;
    component.fills = [solid(index === 1 ? C.v2Coral : C.yellow500)];
    circle(component, `Voice ${state} mic`, 18, 14, 64, C.surface);
    addIcon(component, index === 2 ? "check" : "mic", 38, 34, 24);
    makeText(component, state === "Ready" ? "말해볼래?" : state === "Listening" ? "듣고 있어" : "잘 들었어", 96, 28, 104, 17, "extraBold");
    component.x = 72 + index * 260;
    component.y = 670;
    board.appendChild(component);
    return component;
  });
  const voiceSet = figma.combineAsVariants(voiceComponents, board);
  voiceSet.name = "Voice Button / V2";

  makeText(board, "Emotion Orb / V2", 72, 900, 600, 28, "extraBold");
  const emotionDefinitions = [
    ["신나요", C.v2Coral],
    ["좋아요", C.yellow500],
    ["그냥 그래요", C.v2Aqua],
    ["속상해요", C.v2Sky],
    ["화나요", C.v2Purple],
  ];
  const emotionComponents = emotionDefinitions.map(([label, color], index) => {
    const component = figma.createComponent();
    component.name = `Emotion=${label}`;
    component.resize(170, 190);
    component.fills = [];
    addEmotionFace(component, label, 25, 10, color, index === 1, 120);
    component.x = 72 + index * 210;
    component.y = 960;
    board.appendChild(component);
    return component;
  });
  const emotionSet = figma.combineAsVariants(emotionComponents, board);
  emotionSet.name = "Emotion Orb / V2";

  makeText(board, "Action Button / V2", 72, 1340, 600, 28, "extraBold");
  const actionComponents = ["Default", "Pressed", "Disabled"].map((state, index) => {
    const component = createButtonComponent("도다미와 시작하기", "Primary", state);
    component.resize(300, 68);
    component.cornerRadius = 28;
    component.x = 72 + index * 340;
    component.y = 1400;
    board.appendChild(component);
    return component;
  });
  const actionSet = figma.combineAsVariants(actionComponents, board);
  actionSet.name = "Action Button / V2";

  makeText(board, "Guide moments", 1210, 610, 600, 28, "extraBold");
  rounded(board, "V2 guide stage", 1210, 674, 770, 770, C.v2Sun, 42);
  imageRect(board, "Dodami component guide", IMAGES.brand, 1370, 714, 450, 370);
  rounded(board, "V2 speech cloud", 1260, 1110, 670, 170, C.surface, 52, C.borderStrong);
  makeText(board, "정답은 없어.\n지금 마음을 골라줘!", 1310, 1140, 570, 27, "extraBold", C.ink, "CENTER", 38);
  addStickerBurst(board, 1290, 1330, C.v2Coral, 1.2);
  addStickerBurst(board, 1690, 1338, C.v2Purple, 1);
}

function createMobileScreen(code, title, kind) {
  const screen = makeFrame(`${code} · ${title}`, 390, 844, C.canvas);
  screen.cornerRadius = 32;
  addHeader(screen, title, code, kind !== "entry");

  if (kind === "entry") {
    rounded(screen, "Hero yellow", 0, 0, 390, 520, C.yellow500, 0);
    makeText(screen, "도담", 24, 44, 180, 28, "extraBold");
    rounded(screen, "Guardian entry", 306, 42, 60, 42, C.surface, 18);
    makeText(screen, "보호자", 310, 53, 52, 12, "bold", C.ink, "CENTER");
    imageRect(screen, "Dodami welcome", IMAGES.brand, 58, 112, 274, 274);
    makeText(screen, "안녕! 나는 도다미야.", 36, 408, 318, 28, "extraBold", C.ink, "CENTER");
    makeText(screen, "그림으로 오늘의 마음을 만나볼까?", 44, 462, 302, 16, "regular", C.inkMuted, "CENTER");
    addPrimaryButton(screen, "시작하기", 24, 694, 342, "draw");
    makeText(screen, "보호자와 함께 사용하는 안전한 공간이에요.", 36, 770, 318, 13, "regular", C.inkMuted, "CENTER");
  }

  if (kind === "profile") {
    makeText(screen, "누가 시작할까요?", 24, 126, 342, 28, "extraBold");
    makeText(screen, "내 이름을 골라줘.", 24, 170, 342, 16, "regular", C.inkMuted);
    const names = ["하늘", "별이", "새 친구"];
    const colors = [C.coralSoft, C.mintSoft, C.yellow100];
    names.forEach((name, index) => {
      const y = 228 + index * 142;
      rounded(screen, `Profile / ${name}`, 24, y, 342, 118, C.surface, 24, index === 0 ? C.yellow700 : C.border);
      circle(screen, `${name} avatar`, 44, y + 20, 78, colors[index]);
      if (index < 2) {
        makeText(screen, name, 146, y + 34, 170, 20, "extraBold");
        makeText(screen, index === 0 ? "이어서 할 수 있어요" : "새 활동 시작하기", 146, y + 68, 170, 13, "regular", C.inkMuted);
      } else {
        makeText(screen, "+", 64, y + 29, 38, 28, "bold", C.ink, "CENTER");
        makeText(screen, name, 146, y + 47, 170, 18, "bold");
      }
    });
    addPrimaryButton(screen, "하늘이로 시작하기", 24, 730, 342);
  }

  if (kind === "home") {
    addDodamiBubble(screen, "하늘아, 오늘은 무엇을 해볼까?", 24, 120, 342);
    rounded(screen, "Continue card", 24, 270, 342, 122, C.yellow100, 24);
    makeText(screen, "어제 그리던 숲", 44, 292, 220, 18, "extraBold");
    makeText(screen, "조금만 더 이야기해볼까?", 44, 324, 240, 14, "regular", C.inkMuted);
    rounded(screen, "Continue button", 276, 294, 66, 66, C.yellow500, 22);
    addIcon(screen, "draw", 297, 315, 24);
    addActivityCard(screen, "그림 그리기", "마음 가는 대로 그려봐.", "draw", C.coralSoft, 24, 418, 164, 190);
    addActivityCard(screen, "사진 가져오기", "그린 그림을 찍어볼까?", "camera", C.skySoft, 202, 418, 164, 190);
    rounded(screen, "History row", 24, 626, 342, 82, C.mintSoft, 22);
    addIcon(screen, "history", 46, 655, 24);
    makeText(screen, "지난 활동 보기", 84, 642, 210, 17, "bold");
    makeText(screen, "내가 남긴 그림 4개", 84, 670, 210, 13, "regular", C.inkMuted);
  }

  if (kind === "mode") {
    makeText(screen, "어떻게 시작할까?", 24, 128, 342, 28, "extraBold");
    makeText(screen, "편한 방법을 하나 골라줘.", 24, 172, 342, 16, "regular", C.inkMuted);
    addActivityCard(screen, "바로 그리기", "화면에 손가락으로 그려요.", "draw", C.coralSoft, 24, 228, 342, 208);
    addActivityCard(screen, "사진 가져오기", "종이에 그린 그림을 찍어요.", "camera", C.skySoft, 24, 458, 342, 208);
    makeText(screen, "언제든 홈으로 돌아갈 수 있어.", 24, 716, 342, 13, "regular", C.inkMuted, "CENTER");
  }

  if (kind === "tutorial") {
    imageRect(screen, "Dodami drawing tutorial", IMAGES.drawing, 78, 112, 234, 234);
    makeText(screen, "도다미와 그림 그리기", 24, 348, 342, 26, "extraBold", C.ink, "CENTER");
    const steps = [
      ["1", "색을 골라요", C.coralSoft],
      ["2", "손가락으로 그려요", C.mintSoft],
      ["3", "다 그리면 알려줘요", C.skySoft],
    ];
    steps.forEach(([number, label, color], index) => {
      const y = 410 + index * 76;
      rounded(screen, `Step ${number}`, 24, y, 342, 62, color, 20);
      circle(screen, `Step ${number} number`, 38, y + 12, 38, C.surface);
      makeText(screen, number, 38, y + 18, 38, 15, "bold", C.ink, "CENTER");
      makeText(screen, label, 92, y + 18, 238, 16, "bold");
    });
    addPrimaryButton(screen, "그림 그리러 가기", 24, 714, 342, "draw");
  }

  if (kind === "drawing") {
    addDoodle(screen, 16, 112, 358, 402);
    const toolColors = [C.drawingRed, C.drawingBlue, C.drawingGreen, C.drawingYellow, C.drawingPurple, C.drawingInk];
    toolColors.forEach((color, index) =>
      circle(screen, `Color tool ${index + 1}`, 28 + index * 52, 532, 40, color, index === 2 ? C.ink : undefined),
    );
    rounded(screen, "Eraser", 334, 532, 40, 40, C.surface, 12, C.border);
    addDodamiBubble(screen, "이 숲에는 누가 살고 있어?", 16, 594, 358);
    rounded(screen, "Mic button", 298, 734, 76, 76, C.yellow500, 28);
    addIcon(screen, "mic", 324, 760, 24);
    makeText(screen, "도다미에게 말하기", 28, 755, 244, 16, "bold");
  }

  if (kind === "upload") {
    makeText(screen, "그림을 가져와 볼까?", 24, 126, 342, 28, "extraBold");
    makeText(screen, "그림 전체가 보이게 찍어줘.", 24, 172, 342, 16, "regular", C.inkMuted);
    const zone = rounded(screen, "Upload zone", 24, 232, 342, 330, C.surface, 28, C.borderStrong);
    zone.dashPattern = [10, 8];
    circle(screen, "Camera icon background", 139, 300, 112, C.skySoft);
    addIcon(screen, "camera", 177, 338, 36);
    makeText(screen, "카메라로 찍기", 74, 434, 242, 20, "extraBold", C.ink, "CENTER");
    makeText(screen, "또는 사진에서 고르기", 74, 474, 242, 14, "regular", C.inkMuted, "CENTER");
    addPrimaryButton(screen, "카메라 열기", 24, 604, 342, "camera");
    addSecondaryButton(screen, "사진에서 고르기", 24, 680, 342);
  }

  if (kind === "confirm") {
    makeText(screen, "이 그림이 맞나요?", 24, 126, 342, 28, "extraBold");
    rounded(screen, "Photo preview", 24, 190, 342, 410, C.surface, 28, C.border);
    addDoodle(screen, 44, 210, 302, 370);
    rounded(screen, "Good badge", 42, 540, 126, 42, C.greenSoft, 21);
    addIcon(screen, "check", 56, 549, 24, C.green);
    makeText(screen, "잘 보이네요", 86, 550, 70, 13, "bold", C.green);
    addSecondaryButton(screen, "다시 찍기", 24, 650, 164);
    addPrimaryButton(screen, "이 그림 쓰기", 202, 648, 164);
  }

  if (kind === "uploadDialogue") {
    addDoodle(screen, 24, 116, 342, 300);
    addDodamiBubble(screen, "초록 나무를 많이 그렸네!\n가장 마음에 드는 나무는 뭐야?", 24, 438, 342);
    rounded(screen, "Voice panel", 24, 594, 342, 136, C.surface, 24, C.border);
    circle(screen, "Voice mic", 44, 622, 80, C.yellow500);
    addIcon(screen, "mic", 72, 650, 24);
    makeText(screen, "눌러서 말하기", 146, 624, 170, 18, "extraBold");
    makeText(screen, "천천히 이야기해도 괜찮아.", 146, 660, 180, 13, "regular", C.inkMuted);
    addSecondaryButton(screen, "말하지 않고 넘어가기", 24, 750, 342);
  }

  if (kind === "emotion") {
    makeText(screen, "지금 마음은 어때?", 24, 126, 342, 28, "extraBold");
    makeText(screen, "정답은 없어. 가까운 마음을 골라줘.", 24, 172, 342, 15, "regular", C.inkMuted);
    const choices = [
      ["신나요", C.coralSoft],
      ["좋아요", C.yellow100],
      ["그냥 그래요", C.mintSoft],
      ["속상해요", C.skySoft],
      ["화나요", C.purpleSoft],
    ];
    choices.forEach(([label, color], index) => {
      const x = index < 3 ? 26 + index * 116 : 84 + (index - 3) * 132;
      const y = index < 3 ? 250 : 394;
      rounded(screen, `Choice / ${label}`, x, y, 106, 124, C.surface, 22, index === 1 ? C.yellow700 : C.border);
      addEmotionFace(screen, label, x + 23, y + 15, color, index === 1, 60);
    });
    addDodamiBubble(screen, "좋은 마음도, 어려운 마음도 모두 소중해.", 24, 562, 342);
    addPrimaryButton(screen, "이 마음으로 저장하기", 24, 728, 342);
  }

  if (kind === "complete") {
    [C.coral, C.sky, C.mint, C.purple, C.yellow500].forEach((color, index) => {
      circle(screen, `Confetti ${index + 1}`, 42 + index * 72, 126 + (index % 2) * 42, 14, color);
    });
    imageRect(screen, "Dodami praise", IMAGES.brand, 78, 146, 234, 234);
    makeText(screen, "오늘 마음을 잘 들려줬어!", 24, 390, 342, 26, "extraBold", C.ink, "CENTER");
    makeText(screen, "도다미가 소중하게 저장했어.", 24, 438, 342, 16, "regular", C.inkMuted, "CENTER");
    rounded(screen, "Saved summary", 24, 500, 342, 130, C.yellow50, 24);
    makeText(screen, "오늘의 그림", 44, 522, 160, 13, "bold", C.inkMuted);
    makeText(screen, "초록 숲", 44, 550, 160, 20, "extraBold");
    rounded(screen, "Emotion badge", 240, 530, 102, 72, C.yellow100, 20);
    makeText(screen, "좋아요", 250, 553, 82, 15, "bold", C.ink, "CENTER");
    addPrimaryButton(screen, "홈으로 가기", 24, 690, 342, "home");
  }

  if (kind === "history") {
    makeText(screen, "내가 남긴 마음", 24, 126, 342, 28, "extraBold");
    makeText(screen, "그림을 누르면 다시 볼 수 있어.", 24, 172, 342, 15, "regular", C.inkMuted);
    const items = [
      ["초록 숲", "오늘", C.mintSoft],
      ["우리 가족", "어제", C.coralSoft],
      ["비 오는 날", "7월 24일", C.skySoft],
      ["우주 여행", "7월 20일", C.purpleSoft],
    ];
    items.forEach(([name, date, color], index) => {
      const y = 226 + index * 126;
      rounded(screen, `History / ${name}`, 24, y, 342, 104, C.surface, 22, C.border);
      rounded(screen, `${name} thumbnail`, 36, y + 12, 80, 80, color, 18);
      makeText(screen, name, 138, y + 25, 170, 17, "extraBold");
      makeText(screen, date, 138, y + 57, 170, 13, "regular", C.inkMuted);
    });
  }

  if (kind === "help") {
    imageRect(screen, "Dodami help", IMAGES.brand, 126, 106, 138, 138);
    makeText(screen, "어떤 도움이 필요해?", 24, 248, 342, 26, "extraBold", C.ink, "CENTER");
    const items = [
      ["그림이 잘 안 그려져요", "draw", C.coralSoft],
      ["사진을 가져오고 싶어요", "camera", C.skySoft],
      ["도다미 목소리가 안 들려요", "help", C.mintSoft],
    ];
    items.forEach(([label, icon, color], index) => {
      const y = 312 + index * 90;
      rounded(screen, `Help / ${label}`, 24, y, 342, 72, color, 22);
      addIcon(screen, icon, 44, y + 24, 24);
      makeText(screen, label, 84, y + 22, 244, 16, "bold");
    });
    rounded(screen, "Guardian help", 24, 608, 342, 102, C.surface, 22, C.border);
    makeText(screen, "보호자 도움이 필요해요", 44, 630, 240, 16, "bold");
    makeText(screen, "길게 눌러 보호자 화면을 열어요.", 44, 662, 260, 13, "regular", C.inkMuted);
  }

  if (kind === "exit") {
    addDodamiBubble(screen, "활동을 끝내고 홈으로 갈까?", 24, 134, 342);
    rounded(screen, "Guardian gate", 24, 310, 342, 326, C.surface, 28, C.border);
    circle(screen, "Hold ring outer", 115, 354, 160, C.yellow50, C.yellow700);
    circle(screen, "Hold ring inner", 135, 374, 120, C.yellow500);
    addIcon(screen, "home", 183, 422, 24);
    makeText(screen, "3초 동안 눌러주세요", 72, 534, 246, 20, "extraBold", C.ink, "CENTER");
    makeText(screen, "아이가 실수로 나가지 않도록\n보호자와 함께 확인해요.", 72, 574, 246, 14, "regular", C.inkMuted, "CENTER");
    addSecondaryButton(screen, "계속 활동하기", 24, 690, 342);
  }

  return screen;
}

function addV2TopBar(screen, code, title, accent = C.yellow500) {
  rounded(screen, "V2 top bar", 16, 20, 358, 68, C.surface, 26);
  circle(screen, "V2 back", 26, 30, 48, accent);
  addIcon(screen, "back", 38, 42, 24);
  makeText(screen, code, 90, 31, 74, 12, "extraBold", C.inkMuted);
  makeText(screen, title, 90, 48, 220, 20, "extraBold");
  circle(screen, "V2 help", 316, 30, 48, C.v2Aqua);
  addIcon(screen, "help", 328, 42, 24);
}

function addV2PaperStage(parent, x, y, width, height, name = "V2 sketchbook") {
  rounded(parent, `${name} shadow`, x + 7, y + 9, width, height, "#D5C18B", 28);
  rounded(parent, name, x, y, width, height, C.surface, 28, "#BCA572");
  rounded(parent, `${name} tape left`, x + 22, y - 9, 86, 24, C.yellow100, 5);
  rounded(parent, `${name} tape right`, x + width - 108, y - 9, 86, 24, C.yellow100, 5);
}

function renderMobileEntryV2(screen) {
  addSceneBackdrop(screen, 390, 844, C.yellow500, C.v2Aqua);
  rounded(screen, "Dodam v2 wordmark", 22, 28, 142, 48, C.surface, 24);
  makeText(screen, "도담", 42, 38, 102, 22, "extraBold", C.ink, "CENTER");
  rounded(screen, "Guardian mini gate", 300, 30, 68, 44, C.v2Cream, 22);
  makeText(screen, "보호자", 308, 42, 52, 12, "bold", C.ink, "CENTER");
  imageRect(screen, "Dodami v2 welcome", IMAGES.brand, 50, 112, 292, 286);
  rounded(screen, "V2 welcome cloud", 30, 404, 330, 150, C.surface, 48);
  makeText(screen, "안녕! 도다미야.", 54, 434, 282, 29, "extraBold", C.ink, "CENTER");
  makeText(screen, "오늘의 이야기를 그림으로 만나볼까?", 58, 486, 274, 16, "bold", C.inkMuted, "CENTER");
  addStickerBurst(screen, 54, 574, C.v2Coral, 0.9);
  addStickerBurst(screen, 260, 584, C.v2Purple, 0.8);
  rounded(screen, "V2 start shadow", 24, 716, 342, 68, C.v2Shadow, 28);
  rounded(screen, "V2 start", 24, 708, 342, 68, C.v2Coral, 28);
  makeText(screen, "도다미와 시작하기", 44, 729, 302, 19, "extraBold", C.ink, "CENTER");
}

function renderMobileProfileV2(screen) {
  addSceneBackdrop(screen, 390, 844, C.v2Sun, C.v2Sky);
  addV2TopBar(screen, "C02", "친구 고르기", C.yellow500);
  makeText(screen, "누가 도다미와\n놀러 왔을까?", 28, 118, 250, 31, "extraBold", C.ink, "LEFT", 40);
  imageRect(screen, "Dodami profile peek", IMAGES.brand, 250, 102, 142, 142);
  const profiles = [
    ["하늘", C.v2Coral, "오늘도 반가워!"],
    ["별이", C.v2Aqua, "새 그림을 그려볼까?"],
  ];
  profiles.forEach(([name, color, subtitle], index) => {
    const x = 28 + index * 178;
    rounded(screen, `V2 profile shadow ${name}`, x, 278, 160, 224, C.v2Shadow, 36);
    rounded(screen, `V2 profile ${name}`, x, 270, 160, 224, color, 36, index === 0 ? C.ink : undefined);
    circle(screen, `${name} portrait`, x + 30, 294, 100, C.surface);
    addEmotionFace(screen, "", x + 48, 312, C.yellow100, false, 64);
    makeText(screen, name, x + 16, 410, 128, 22, "extraBold", C.ink, "CENTER");
    makeText(screen, subtitle, x + 16, 446, 128, 12, "bold", C.inkMuted, "CENTER");
  });
  addTactileTile(screen, "V2 add profile", 28, 542, 334, 126, C.v2Cream, "새 친구 만나기", "check");
  rounded(screen, "V2 profile continue", 28, 732, 334, 64, C.yellow500, 28);
  makeText(screen, "하늘이로 시작하기", 48, 751, 294, 18, "extraBold", C.ink, "CENTER");
}

function renderMobileHomeV2(screen) {
  addSceneBackdrop(screen, 390, 844, C.yellow500, C.v2Aqua);
  rounded(screen, "V2 home header", 18, 20, 354, 82, C.surface, 30);
  makeText(screen, "하늘아, 안녕!", 34, 35, 220, 22, "extraBold");
  makeText(screen, "오늘은 무엇을 해볼까?", 34, 66, 236, 14, "bold", C.inkMuted);
  circle(screen, "V2 home history", 306, 31, 52, C.v2Sun);
  addIcon(screen, "history", 320, 45, 24);
  imageRect(screen, "Dodami home guide", IMAGES.brand, 226, 108, 164, 154);
  rounded(screen, "V2 home speech", 18, 122, 240, 112, C.surface, 36);
  makeText(screen, "하고 싶은 놀이를\n하나 골라봐!", 42, 148, 192, 21, "extraBold", C.ink, "CENTER", 30);
  addTactileTile(screen, "V2 home draw", 18, 286, 172, 186, C.v2Coral, "그림 그리기", "draw");
  addTactileTile(screen, "V2 home camera", 204, 286, 168, 186, C.v2Sky, "사진 가져오기", "camera");
  addTactileTile(screen, "V2 home talk", 18, 492, 172, 162, C.v2Aqua, "도다미와 대화", "mic");
  addTactileTile(screen, "V2 home gallery", 204, 492, 168, 162, C.v2Leaf, "내 그림 보기", "history");
  rounded(screen, "V2 continue strip shadow", 18, 704, 354, 92, C.v2Shadow, 28);
  rounded(screen, "V2 continue strip", 18, 696, 354, 92, C.v2Cream, 28);
  makeText(screen, "어제 그리던 초록 숲", 40, 714, 220, 17, "extraBold");
  makeText(screen, "이어서 이야기할 수 있어", 40, 744, 220, 13, "bold", C.inkMuted);
  circle(screen, "Continue play", 300, 710, 60, C.yellow500);
  addIcon(screen, "draw", 318, 728, 24);
}

function renderMobileTopicV2(screen) {
  rounded(screen, "Topic scene", 0, 0, 390, 844, C.v2Sun, 0);
  addV2TopBar(screen, "C04", "그림 주제 고르기", C.v2Coral);
  makeText(screen, "오늘은 어떤 이야기를\n그려볼까?", 24, 116, 342, 29, "extraBold", C.ink, "CENTER", 38);
  const topics = [
    ["우리 가족", C.v2Coral, "home"],
    ["즐거웠던 하루", C.v2Aqua, "check"],
    ["상상 속 친구", C.v2Purple, "help"],
    ["자유롭게 그리기", C.v2Sky, "draw"],
  ];
  topics.forEach(([label, color, icon], index) => {
    const col = index % 2;
    const row = Math.floor(index / 2);
    const x = 22 + col * 182;
    const y = 228 + row * 220;
    addTactileTile(screen, `V2 topic ${label}`, x, y, 166, 188, color, label, icon);
    circle(screen, `${label} scene dot`, x + 102, y + 34, 42, C.yellow500);
    rounded(screen, `${label} scene hill`, x + 74, y + 78, 72, 34, C.v2Leaf, 18);
  });
  rounded(screen, "V2 topic next", 22, 706, 346, 64, C.yellow500, 28);
  makeText(screen, "이 주제로 그리기", 42, 725, 306, 18, "extraBold", C.ink, "CENTER");
}

function renderMobileTutorialV2(screen) {
  addSceneBackdrop(screen, 390, 844, C.v2Aqua, C.v2Leaf);
  addV2TopBar(screen, "C05", "그림 놀이 준비", C.yellow500);
  imageRect(screen, "Dodami tutorial v2", IMAGES.drawing, 72, 106, 246, 220);
  rounded(screen, "Tutorial speech cloud", 30, 312, 330, 96, C.surface, 36);
  makeText(screen, "세 가지만 기억하면 돼!", 50, 340, 290, 22, "extraBold", C.ink, "CENTER");
  const steps = [
    ["1", "크레용을 골라요", C.v2Coral],
    ["2", "종이에 쓱쓱 그려요", C.yellow500],
    ["3", "도다미에게 들려줘요", C.v2Purple],
  ];
  steps.forEach(([number, label, color], index) => {
    const y = 436 + index * 82;
    rounded(screen, `V2 tutorial ${number} shadow`, 30, y + 6, 330, 66, C.v2Shadow, 24);
    rounded(screen, `V2 tutorial ${number}`, 30, y, 330, 66, color, 24);
    circle(screen, `V2 tutorial number ${number}`, 44, y + 10, 46, C.surface);
    makeText(screen, number, 44, y + 19, 46, 17, "extraBold", C.ink, "CENTER");
    makeText(screen, label, 106, y + 19, 224, 17, "extraBold");
  });
  rounded(screen, "V2 tutorial start", 30, 714, 330, 64, C.v2Coral, 28);
  makeText(screen, "스케치북 열기", 50, 733, 290, 18, "extraBold", C.ink, "CENTER");
}

function renderMobileDrawingV2(screen, uploaded = false) {
  rounded(screen, "V2 drawing room", 0, 0, 390, 844, C.v2Aqua, 0);
  addV2TopBar(screen, uploaded ? "C09" : "C06", uploaded ? "그림 이야기" : "나의 스케치북", C.yellow500);
  const paperHeight = uploaded ? 410 : 500;
  const trayY = uploaded ? 538 : 574;
  const conversationY = uploaded ? 632 : 658;
  addV2PaperStage(screen, 14, 112, 362, paperHeight);
  addDoodle(screen, 30, 132, 330, paperHeight - 44);
  addCrayonTray(screen, 18, trayY, 354, true);
  rounded(screen, "V2 drawing conversation", 18, conversationY, 354, uploaded ? 134 : 120, C.v2Sun, 34);
  imageRect(screen, "Dodami drawing question", IMAGES.brand, 20, conversationY + 6, 116, 108);
  makeText(
    screen,
    uploaded ? "가장 마음에 드는\n나무는 뭐야?" : "이 숲에는\n누가 살고 있어?",
    132,
    conversationY + 22,
    150,
    17,
    "extraBold",
    C.ink,
    "CENTER",
    24,
  );
  circle(screen, "V2 drawing mic shadow", 294, conversationY + 24, 64, C.v2Shadow);
  circle(screen, "V2 drawing mic", 294, conversationY + 18, 64, C.v2Coral);
  addIcon(screen, "mic", 314, conversationY + 38, 24);
  rounded(screen, "V2 drawing done", 18, 788, 354, 42, C.yellow500, 21);
  makeText(screen, "다 그렸어요", 38, 797, 314, 15, "extraBold", C.ink, "CENTER");
}

function renderMobileUploadV2(screen, confirm = false) {
  rounded(screen, "V2 camera world", 0, 0, 390, 844, confirm ? C.v2Sun : C.v2Sky, 0);
  addV2TopBar(screen, confirm ? "C08" : "C07", confirm ? "그림 확인하기" : "그림 사진 찍기", C.yellow500);
  makeText(screen, confirm ? "이 그림이 맞아?" : "종이 그림이 네모 안에\n쏙 들어오게 해줘!", 28, 116, 334, 27, "extraBold", C.ink, "CENTER", 36);
  addV2PaperStage(screen, 30, 224, 330, 390, "V2 camera paper");
  if (confirm) {
    addDoodle(screen, 48, 246, 294, 344);
  } else {
    const zone = rounded(screen, "V2 camera focus", 52, 250, 286, 332, C.surface, 22, C.ink);
    zone.opacity = 0.46;
    circle(screen, "V2 camera preview icon", 145, 346, 100, C.v2Sky);
    addIcon(screen, "camera", 178, 379, 34);
  }
  if (confirm) {
    rounded(screen, "V2 retake", 30, 680, 154, 64, C.surface, 26, C.ink);
    makeText(screen, "다시 찍기", 48, 699, 118, 17, "extraBold", C.ink, "CENTER");
    rounded(screen, "V2 use photo", 202, 680, 158, 64, C.v2Coral, 26);
    makeText(screen, "이 그림 쓰기", 220, 699, 122, 17, "extraBold", C.ink, "CENTER");
  } else {
    circle(screen, "V2 shutter shadow", 146, 674, 98, C.v2Shadow);
    circle(screen, "V2 shutter", 146, 666, 98, C.yellow500, C.surface);
    circle(screen, "V2 shutter inner", 169, 689, 52, C.surface);
    makeText(screen, "사진에서 고르기", 106, 782, 178, 14, "extraBold", C.ink, "CENTER");
  }
}

function renderMobileEmotionV2(screen) {
  rounded(screen, "V2 emotion sky", 0, 0, 390, 844, C.v2Purple, 0);
  addV2TopBar(screen, "C10", "마음 고르기", C.yellow500);
  imageRect(screen, "Dodami emotion guide", IMAGES.brand, 130, 94, 130, 124);
  rounded(screen, "V2 emotion cloud", 28, 202, 334, 104, C.surface, 42);
  makeText(screen, "지금 마음은 어때?\n정답은 없어.", 52, 226, 286, 22, "extraBold", C.ink, "CENTER", 31);
  const choices = [
    ["신나요", C.v2Coral, 36, 350],
    ["좋아요", C.yellow500, 142, 326],
    ["그냥 그래요", C.v2Aqua, 248, 350],
    ["속상해요", C.v2Sky, 84, 504],
    ["화나요", C.v2Purple, 212, 504],
  ];
  choices.forEach(([label, color, x, y], index) => {
    const orbX = Number(x);
    const orbY = Number(y);
    circle(screen, `V2 emotion halo ${label}`, orbX - 6, orbY - 6, 112, index === 1 ? C.surface : C.v2Sun);
    addEmotionFace(screen, String(label), orbX, orbY, String(color), index === 1, 100);
  });
  circle(screen, "V2 selected emotion check", 218, 324, 32, C.ink);
  addIcon(screen, "check", 222, 328, 24, C.surface);
  rounded(screen, "V2 emotion save shadow", 28, 744, 334, 64, C.v2Shadow, 28);
  rounded(screen, "V2 emotion save", 28, 736, 334, 64, C.yellow500, 28);
  makeText(screen, "이 마음으로 저장하기", 48, 755, 294, 18, "extraBold", C.ink, "CENTER");
}

function renderMobileCompleteV2(screen) {
  addSceneBackdrop(screen, 390, 844, C.v2Sun, C.v2Aqua);
  addStickerBurst(screen, 30, 86, C.v2Coral, 1);
  addStickerBurst(screen, 262, 102, C.v2Purple, 1);
  makeText(screen, "정말 멋진 이야기야!", 30, 76, 330, 28, "extraBold", C.ink, "CENTER");
  imageRect(screen, "Dodami v2 praise", IMAGES.brand, 232, 130, 150, 146);
  addV2PaperStage(screen, 28, 196, 302, 346, "V2 framed artwork");
  addDoodle(screen, 46, 218, 266, 302);
  rounded(screen, "V2 praise cloud", 30, 572, 330, 108, C.surface, 40);
  makeText(screen, "초록 나무를 가득 그렸네!\n도다미가 소중히 기억할게.", 52, 596, 286, 18, "extraBold", C.ink, "CENTER", 27);
  rounded(screen, "V2 complete home shadow", 30, 736, 330, 64, C.v2Shadow, 28);
  rounded(screen, "V2 complete home", 30, 728, 330, 64, C.v2Coral, 28);
  makeText(screen, "집으로 가기", 50, 747, 290, 18, "extraBold", C.ink, "CENTER");
}

function renderMobileHistoryV2(screen) {
  rounded(screen, "V2 gallery wall", 0, 0, 390, 844, "#F8DCA6", 0);
  addV2TopBar(screen, "C12", "나의 그림 전시회", C.yellow500);
  makeText(screen, "도다미와 만든 이야기가\n벽에 걸려 있어!", 24, 116, 342, 25, "extraBold", C.ink, "CENTER", 34);
  const items = [
    ["초록 숲", C.v2Aqua],
    ["우리 가족", C.v2Coral],
    ["비 오는 날", C.v2Sky],
    ["우주 여행", C.v2Purple],
  ];
  items.forEach(([label, color], index) => {
    const col = index % 2;
    const row = Math.floor(index / 2);
    const x = 24 + col * 180;
    const y = 230 + row * 236;
    rounded(screen, `V2 frame shadow ${label}`, x + 5, y + 7, 158, 190, "#9F6C3E", 12);
    rounded(screen, `V2 art frame ${label}`, x, y, 158, 190, "#C68A4B", 12);
    rounded(screen, `${label} artwork`, x + 14, y + 14, 130, 126, color, 8);
    makeText(screen, label, x + 14, y + 150, 130, 16, "extraBold", C.v2Cream, "CENTER");
  });
  imageRect(screen, "Dodami gallery", IMAGES.brand, 248, 686, 136, 126);
}

function renderMobileHelpV2(screen, exit = false) {
  addSceneBackdrop(screen, 390, 844, exit ? C.v2Sun : C.v2Aqua, C.v2Leaf);
  addV2TopBar(screen, exit ? "C14" : "C13", exit ? "집으로 가기" : "도다미 도움", C.yellow500);
  imageRect(screen, "Dodami help v2", IMAGES.brand, 92, 108, 206, 194);
  rounded(screen, "V2 help cloud", 28, 288, 334, 122, C.surface, 42);
  makeText(
    screen,
    exit ? "활동을 마치고\n집으로 갈까?" : "무엇이 어려운지\n도다미에게 알려줘!",
    52,
    318,
    286,
    22,
    "extraBold",
    C.ink,
    "CENTER",
    31,
  );
  if (exit) {
    circle(screen, "V2 hold shadow", 101, 462, 188, C.v2Shadow);
    circle(screen, "V2 hold action", 101, 452, 188, C.v2Coral, C.surface);
    circle(screen, "V2 hold inner", 130, 481, 130, C.yellow500);
    addIcon(screen, "home", 183, 522, 24);
    makeText(screen, "3초 동안 꾹", 126, 574, 138, 17, "extraBold", C.ink, "CENTER");
    rounded(screen, "V2 keep playing", 32, 734, 326, 60, C.surface, 26, C.ink);
    makeText(screen, "조금 더 놀기", 52, 752, 286, 17, "extraBold", C.ink, "CENTER");
  } else {
    addTactileTile(screen, "V2 help draw", 28, 452, 334, 112, C.v2Coral, "그림이 잘 안 그려져요", "draw");
    addTactileTile(screen, "V2 help sound", 28, 590, 334, 112, C.v2Sky, "도다미 목소리가 안 들려요", "help");
    rounded(screen, "V2 guardian help", 28, 744, 334, 54, C.yellow500, 24);
    makeText(screen, "보호자와 함께 보기", 48, 759, 294, 16, "extraBold", C.ink, "CENTER");
  }
}

function createMobileScreenV2(code, title, kind) {
  const screen = makeFrame(`${code} · ${title} · V2`, 390, 844, C.v2Sun);
  screen.cornerRadius = 32;
  if (kind === "entry") renderMobileEntryV2(screen);
  else if (kind === "profile") renderMobileProfileV2(screen);
  else if (kind === "home") renderMobileHomeV2(screen);
  else if (kind === "mode") renderMobileTopicV2(screen);
  else if (kind === "tutorial") renderMobileTutorialV2(screen);
  else if (kind === "drawing") renderMobileDrawingV2(screen, false);
  else if (kind === "upload") renderMobileUploadV2(screen, false);
  else if (kind === "confirm") renderMobileUploadV2(screen, true);
  else if (kind === "uploadDialogue") renderMobileDrawingV2(screen, true);
  else if (kind === "emotion") renderMobileEmotionV2(screen);
  else if (kind === "complete") renderMobileCompleteV2(screen);
  else if (kind === "history") renderMobileHistoryV2(screen);
  else if (kind === "help") renderMobileHelpV2(screen, false);
  else renderMobileHelpV2(screen, true);
  return screen;
}

function createTabletScreen(code, title, kind) {
  const screen = makeFrame(`${code} · ${title} · Tablet`, 1194, 834, C.canvas);
  screen.cornerRadius = 28;
  addHeader(screen, title, code, true);
  rounded(screen, "Tablet nav rail", 24, 116, 88, 678, C.surface, 28, C.border);
  ["home", "draw", "camera", "history", "help"].forEach((icon, index) => {
    if (index === 0) rounded(screen, "Active nav", 36, 140 + index * 92, 64, 64, C.yellow100, 20);
    addIcon(screen, icon, 56, 160 + index * 92, 24);
  });

  const left = 144;
  const contentWidth = 1018;

  if (kind === "home") {
    rounded(screen, "Hero panel", left, 116, contentWidth, 220, C.yellow100, 32);
    makeText(screen, "하늘아, 오늘은 무엇을 해볼까?", left + 36, 156, 560, 32, "extraBold");
    makeText(screen, "도다미가 옆에서 기다리고 있어.", left + 36, 214, 500, 18, "regular", C.inkMuted);
    imageRect(screen, "Dodami tablet home", IMAGES.brand, 842, 120, 276, 210);
    addActivityCard(screen, "그림 그리기", "마음 가는 대로 그려봐.", "draw", C.coralSoft, left, 370, 300, 210);
    addActivityCard(screen, "사진 가져오기", "종이 그림을 찍어봐.", "camera", C.skySoft, left + 326, 370, 300, 210);
    addActivityCard(screen, "지난 활동", "내 그림을 다시 만나봐.", "history", C.mintSoft, left + 652, 370, 300, 210);
    rounded(screen, "Continue tablet", left, 612, 952, 140, C.surface, 28, C.border);
    makeText(screen, "어제 그리던 숲", left + 32, 640, 400, 22, "extraBold");
    makeText(screen, "조금만 더 이야기해볼까?", left + 32, 682, 400, 16, "regular", C.inkMuted);
    addPrimaryButton(screen, "이어서 하기", left + 700, 650, 220);
  } else if (kind === "drawing" || kind === "uploadDialogue") {
    addDoodle(screen, left, 116, 626, 560);
    rounded(screen, "Dialogue side panel", 794, 116, 368, 560, C.surface, 30, C.border);
    imageRect(screen, "Dodami dialogue", IMAGES.brand, 864, 136, 228, 180);
    makeText(screen, kind === "drawing" ? "이 숲에는 누가 살고 있어?" : "가장 마음에 드는 나무는 뭐야?", 826, 336, 304, 24, "extraBold", C.ink, "CENTER");
    rounded(screen, "Voice action", 826, 446, 304, 124, C.yellow50, 24);
    circle(screen, "Voice mic", 846, 468, 80, C.yellow500);
    addIcon(screen, "mic", 874, 496, 24);
    makeText(screen, "눌러서 말하기", 950, 474, 150, 18, "bold");
    makeText(screen, "천천히 말해도 괜찮아.", 950, 512, 160, 13, "regular", C.inkMuted);
    const colors = [C.drawingRed, C.drawingBlue, C.drawingGreen, C.drawingYellow, C.drawingPurple, C.drawingInk];
    colors.forEach((color, index) => circle(screen, `Tablet color ${index + 1}`, left + index * 60, 704, 44, color));
    addPrimaryButton(screen, "다 그렸어요", 900, 704, 262);
  } else if (kind === "emotion") {
    makeText(screen, "지금 마음은 어때?", left, 132, 700, 34, "extraBold");
    makeText(screen, "정답은 없어. 가장 가까운 마음을 골라줘.", left, 188, 700, 18, "regular", C.inkMuted);
    const choices = [
      ["신나요", C.coralSoft],
      ["좋아요", C.yellow100],
      ["그냥 그래요", C.mintSoft],
      ["속상해요", C.skySoft],
      ["화나요", C.purpleSoft],
    ];
    choices.forEach(([label, color], index) => {
      const x = left + index * 196;
      rounded(screen, `Tablet emotion ${label}`, x, 276, 172, 210, C.surface, 28, index === 1 ? C.yellow700 : C.border);
      addEmotionFace(screen, label, x + 46, 306, color, index === 1, 80);
    });
    addDodamiBubble(screen, "좋은 마음도, 어려운 마음도 모두 소중해.", left, 548, 660);
    addPrimaryButton(screen, "이 마음으로 저장하기", 870, 582, 292);
  } else if (kind === "complete") {
    rounded(screen, "Completion panel", left, 116, contentWidth, 636, C.yellow50, 36);
    imageRect(screen, "Dodami tablet complete", IMAGES.brand, left + 90, 194, 390, 390);
    makeText(screen, "오늘 마음을 잘 들려줬어!", left + 518, 224, 430, 36, "extraBold");
    makeText(screen, "도다미가 소중하게 저장했어.", left + 518, 292, 430, 18, "regular", C.inkMuted);
    rounded(screen, "Tablet summary", left + 518, 360, 390, 150, C.surface, 28, C.border);
    makeText(screen, "오늘의 그림", left + 550, 388, 160, 14, "bold", C.inkMuted);
    makeText(screen, "초록 숲", left + 550, 426, 160, 24, "extraBold");
    rounded(screen, "Emotion", left + 760, 390, 116, 76, C.yellow100, 22);
    makeText(screen, "좋아요", left + 772, 414, 92, 16, "bold", C.ink, "CENTER");
    addPrimaryButton(screen, "홈으로 가기", left + 518, 566, 390, "home");
  } else if (kind === "tutorial") {
    imageRect(screen, "Dodami tablet drawing", IMAGES.drawing, left, 146, 450, 450);
    makeText(screen, "도다미와 그림 그리기", 650, 148, 450, 34, "extraBold");
    const steps = [
      ["1", "색을 골라요", C.coralSoft],
      ["2", "손가락으로 그려요", C.mintSoft],
      ["3", "다 그리면 알려줘요", C.skySoft],
    ];
    steps.forEach(([number, label, color], index) => {
      const y = 230 + index * 112;
      rounded(screen, `Tablet step ${number}`, 650, y, 480, 88, color, 24);
      circle(screen, `Tablet step number ${number}`, 670, y + 17, 54, C.surface);
      makeText(screen, number, 670, y + 30, 54, 18, "bold", C.ink, "CENTER");
      makeText(screen, label, 752, y + 27, 330, 20, "bold");
    });
    addPrimaryButton(screen, "그림 그리러 가기", 650, 606, 480, "draw");
  } else if (kind === "history") {
    makeText(screen, "내가 남긴 마음", left, 132, 600, 34, "extraBold");
    const items = [
      ["초록 숲", "오늘", C.mintSoft],
      ["우리 가족", "어제", C.coralSoft],
      ["비 오는 날", "7월 24일", C.skySoft],
      ["우주 여행", "7월 20일", C.purpleSoft],
      ["커다란 고래", "7월 18일", C.skySoft],
      ["우리 집", "7월 15일", C.yellow100],
    ];
    items.forEach(([name, date, color], index) => {
      const col = index % 3;
      const row = Math.floor(index / 3);
      const x = left + col * 330;
      const y = 220 + row * 250;
      rounded(screen, `Tablet history ${name}`, x, y, 300, 218, C.surface, 26, C.border);
      rounded(screen, `${name} art`, x + 16, y + 16, 268, 126, color, 20);
      makeText(screen, name, x + 20, y + 158, 170, 18, "extraBold");
      makeText(screen, date, x + 200, y + 160, 80, 13, "regular", C.inkMuted, "RIGHT");
    });
  } else {
    makeText(screen, title, left, 132, 600, 34, "extraBold");
    makeText(screen, "모바일 흐름을 태블릿의 넓은 화면에 맞춰 구성했어요.", left, 188, 760, 18, "regular", C.inkMuted);
    rounded(screen, "Tablet main content", left, 246, 630, 430, C.surface, 32, C.border);
    if (kind === "upload" || kind === "confirm") {
      addDoodle(screen, left + 30, 276, 570, 360);
    } else {
      imageRect(screen, "Dodami tablet", IMAGES.brand, left + 110, 280, 410, 350);
    }
    rounded(screen, "Tablet action panel", 804, 246, 358, 430, C.yellow50, 32);
    makeText(screen, kind === "help" ? "어떤 도움이 필요해?" : "도다미와 함께 다음으로 갈까?", 836, 294, 294, 26, "extraBold", C.ink, "CENTER");
    makeText(screen, "짧고 쉬운 안내와\n한 가지 주요 행동만 보여줘요.", 836, 386, 294, 17, "regular", C.inkMuted, "CENTER");
    addPrimaryButton(screen, kind === "exit" ? "3초 동안 누르기" : "다음으로", 836, 540, 294);
  }

  return screen;
}

function addTabletV2TopBar(screen, code, title) {
  rounded(screen, "Tablet V2 top ribbon", 28, 22, 1138, 72, C.surface, 30);
  circle(screen, "Tablet V2 back", 40, 32, 52, C.yellow500);
  addIcon(screen, "back", 54, 46, 24);
  makeText(screen, code, 112, 36, 90, 13, "extraBold", C.inkMuted);
  makeText(screen, title, 112, 54, 520, 21, "extraBold");
  rounded(screen, "Tablet V2 home pill", 1018, 34, 132, 48, C.v2Aqua, 24);
  addIcon(screen, "home", 1034, 46, 24);
  makeText(screen, "놀이방", 1064, 47, 70, 15, "extraBold", C.ink, "CENTER");
}

function renderTabletHomeV2(screen) {
  addSceneBackdrop(screen, 1194, 834, C.yellow500, C.v2Aqua);
  rounded(screen, "Tablet V2 wordmark", 34, 28, 146, 52, C.surface, 26);
  makeText(screen, "도담", 54, 41, 106, 22, "extraBold", C.ink, "CENTER");
  makeText(screen, "하늘아, 오늘은\n무엇을 해볼까?", 54, 154, 430, 44, "extraBold", C.ink, "LEFT", 56);
  rounded(screen, "Tablet home speech", 50, 288, 430, 92, C.surface, 40);
  makeText(screen, "하고 싶은 놀이를 하나 골라봐!", 76, 317, 378, 20, "extraBold", C.ink, "CENTER");
  imageRect(screen, "Tablet Dodami home v2", IMAGES.brand, 126, 390, 340, 330);
  addTactileTile(screen, "Tablet V2 draw", 526, 132, 290, 258, C.v2Coral, "그림 그리기", "draw");
  addTactileTile(screen, "Tablet V2 camera", 844, 132, 290, 258, C.v2Sky, "사진 가져오기", "camera");
  addTactileTile(screen, "Tablet V2 talk", 526, 426, 290, 226, C.v2Aqua, "도다미와 대화", "mic");
  addTactileTile(screen, "Tablet V2 gallery", 844, 426, 290, 226, C.v2Leaf, "내 그림 전시회", "history");
  rounded(screen, "Tablet V2 continue", 526, 696, 608, 96, C.v2Cream, 30);
  makeText(screen, "어제 그리던 초록 숲", 556, 716, 320, 20, "extraBold");
  makeText(screen, "바로 이어서 이야기할 수 있어", 556, 750, 340, 14, "bold", C.inkMuted);
  circle(screen, "Tablet continue action", 1056, 712, 64, C.yellow500);
  addIcon(screen, "draw", 1076, 732, 24);
}

function renderTabletTopicV2(screen) {
  rounded(screen, "Tablet topic world", 0, 0, 1194, 834, C.v2Sun, 0);
  addTabletV2TopBar(screen, "C04", "그림 주제 고르기");
  imageRect(screen, "Tablet topic Dodami", IMAGES.brand, 44, 128, 300, 282);
  rounded(screen, "Tablet topic cloud", 54, 400, 310, 116, C.surface, 42);
  makeText(screen, "어떤 이야기를\n그려볼까?", 84, 430, 250, 27, "extraBold", C.ink, "CENTER", 36);
  const topics = [
    ["우리 가족", C.v2Coral, "home"],
    ["즐거웠던 하루", C.v2Aqua, "check"],
    ["상상 속 친구", C.v2Purple, "help"],
    ["자유롭게 그리기", C.v2Sky, "draw"],
  ];
  topics.forEach(([label, color, icon], index) => {
    const col = index % 2;
    const row = Math.floor(index / 2);
    const x = 420 + col * 360;
    const y = 136 + row * 302;
    addTactileTile(screen, `Tablet topic ${label}`, x, y, 324, 260, color, label, icon);
    circle(screen, `${label} tablet sun`, x + 226, y + 38, 54, C.yellow500);
    rounded(screen, `${label} tablet hill`, x + 184, y + 108, 102, 48, C.v2Leaf, 24);
  });
}

function renderTabletDrawingV2(screen, uploaded = false) {
  rounded(screen, "Tablet V2 studio", 0, 0, 1194, 834, C.v2Aqua, 0);
  addTabletV2TopBar(screen, uploaded ? "C09" : "C06", uploaded ? "그림 이야기" : "나의 스케치북");
  rounded(screen, "Tablet tool shelf shadow", 28, 126, 108, 642, "#A77B54", 28);
  rounded(screen, "Tablet tool shelf", 22, 118, 108, 642, "#F2C987", 28, "#9D7048");
  const toolKinds = ["draw", "check", "close", "camera", "help"];
  toolKinds.forEach((icon, index) => {
    circle(screen, `Tablet studio tool ${index + 1}`, 42, 148 + index * 104, 68, index === 0 ? C.yellow500 : C.surface);
    addIcon(screen, icon, 64, 170 + index * 104, 24);
  });
  addV2PaperStage(screen, 158, 124, 650, 540, "Tablet V2 sketchbook");
  addDoodle(screen, 182, 150, 602, 486);
  addCrayonTray(screen, 170, 690, 626, true);
  rounded(screen, "Tablet V2 Dodami stage", 834, 124, 334, 640, C.v2Sun, 38);
  imageRect(screen, "Tablet drawing Dodami v2", IMAGES.brand, 884, 146, 236, 230);
  rounded(screen, "Tablet drawing speech", 864, 376, 274, 136, C.surface, 42);
  makeText(
    screen,
    uploaded ? "가장 마음에 드는\n나무는 뭐야?" : "이 숲에는\n누가 살고 있어?",
    892,
    408,
    218,
    24,
    "extraBold",
    C.ink,
    "CENTER",
    34,
  );
  circle(screen, "Tablet V2 mic shadow", 956, 548, 92, C.v2Shadow);
  circle(screen, "Tablet V2 mic", 956, 538, 92, C.v2Coral);
  addIcon(screen, "mic", 990, 572, 24);
  rounded(screen, "Tablet V2 done", 870, 664, 264, 64, C.yellow500, 28);
  makeText(screen, "다 그렸어요", 894, 683, 216, 18, "extraBold", C.ink, "CENTER");
}

function renderTabletEmotionV2(screen) {
  rounded(screen, "Tablet V2 emotion world", 0, 0, 1194, 834, C.v2Purple, 0);
  addTabletV2TopBar(screen, "C10", "마음 고르기");
  imageRect(screen, "Tablet emotion Dodami v2", IMAGES.brand, 50, 138, 300, 286);
  rounded(screen, "Tablet emotion cloud", 44, 426, 320, 126, C.surface, 44);
  makeText(screen, "지금 마음은 어때?\n정답은 없어.", 72, 456, 264, 26, "extraBold", C.ink, "CENTER", 36);
  const choices = [
    ["신나요", C.v2Coral],
    ["좋아요", C.yellow500],
    ["그냥 그래요", C.v2Aqua],
    ["속상해요", C.v2Sky],
    ["화나요", "#B566DE"],
  ];
  choices.forEach(([label, color], index) => {
    const x = 420 + (index % 3) * 238 + (index > 2 ? 118 : 0);
    const y = index < 3 ? 162 : 430;
    circle(screen, `Tablet emotion halo ${label}`, x - 10, y - 10, 184, index === 1 ? C.surface : C.v2Sun);
    addEmotionFace(screen, label, x, y, color, index === 1, 164);
  });
  circle(screen, "Tablet selected emotion check", 788, 158, 38, C.ink);
  addIcon(screen, "check", 795, 165, 24, C.surface);
  rounded(screen, "Tablet emotion save", 780, 716, 354, 64, C.yellow500, 28);
  makeText(screen, "이 마음으로 저장하기", 804, 735, 306, 18, "extraBold", C.ink, "CENTER");
}

function renderTabletCompleteV2(screen) {
  addSceneBackdrop(screen, 1194, 834, C.v2Sun, C.v2Aqua);
  makeText(screen, "정말 멋진 이야기야!", 64, 56, 1066, 40, "extraBold", C.ink, "CENTER");
  addStickerBurst(screen, 70, 124, C.v2Coral, 1.4);
  addStickerBurst(screen, 980, 122, C.v2Purple, 1.3);
  addV2PaperStage(screen, 74, 158, 580, 520, "Tablet V2 framed artwork");
  addDoodle(screen, 104, 188, 520, 460);
  rounded(screen, "Tablet praise stage", 700, 148, 424, 540, C.v2Coral, 42);
  imageRect(screen, "Tablet praise Dodami v2", IMAGES.brand, 760, 170, 304, 292);
  rounded(screen, "Tablet praise cloud", 738, 464, 348, 126, C.surface, 44);
  makeText(screen, "초록 나무를 가득 그렸네!\n도다미가 기억할게.", 766, 494, 292, 22, "extraBold", C.ink, "CENTER", 32);
  rounded(screen, "Tablet complete home", 738, 614, 348, 64, C.yellow500, 28);
  makeText(screen, "집으로 가기", 762, 633, 300, 18, "extraBold", C.ink, "CENTER");
}

function renderTabletTutorialV2(screen) {
  addSceneBackdrop(screen, 1194, 834, C.v2Aqua, C.v2Leaf);
  addTabletV2TopBar(screen, "C05", "그림 놀이 준비");
  imageRect(screen, "Tablet tutorial Dodami v2", IMAGES.drawing, 42, 126, 470, 470);
  makeText(screen, "세 가지만 기억하면 돼!", 552, 138, 572, 34, "extraBold", C.ink, "CENTER");
  const steps = [
    ["1", "크레용을 골라요", C.v2Coral],
    ["2", "종이에 쓱쓱 그려요", C.yellow500],
    ["3", "도다미에게 들려줘요", C.v2Purple],
  ];
  steps.forEach(([number, label, color], index) => {
    const y = 222 + index * 136;
    rounded(screen, `Tablet V2 tutorial shadow ${number}`, 576, y + 8, 520, 104, C.v2Shadow, 32);
    rounded(screen, `Tablet V2 tutorial ${number}`, 576, y, 520, 104, color, 32);
    circle(screen, `Tablet V2 tutorial number ${number}`, 596, y + 18, 68, C.surface);
    makeText(screen, number, 596, y + 36, 68, 20, "extraBold", C.ink, "CENTER");
    makeText(screen, label, 692, y + 34, 364, 22, "extraBold");
  });
  rounded(screen, "Tablet tutorial open", 576, 662, 520, 70, C.v2Coral, 30);
  makeText(screen, "스케치북 열기", 600, 684, 472, 19, "extraBold", C.ink, "CENTER");
}

function renderTabletCameraV2(screen, confirm = false) {
  rounded(screen, "Tablet V2 camera world", 0, 0, 1194, 834, confirm ? C.v2Sun : C.v2Sky, 0);
  addTabletV2TopBar(screen, confirm ? "C08" : "C07", confirm ? "그림 확인하기" : "그림 사진 찍기");
  imageRect(screen, "Tablet camera Dodami v2", IMAGES.brand, 48, 142, 330, 310);
  rounded(screen, "Tablet camera speech", 48, 454, 330, 120, C.surface, 42);
  makeText(screen, confirm ? "이 그림이 맞아?" : "그림 전체가\n네모 안에 보이게!", 78, 484, 270, 24, "extraBold", C.ink, "CENTER", 34);
  addV2PaperStage(screen, 430, 132, 690, 540, "Tablet V2 camera paper");
  if (confirm) addDoodle(screen, 464, 166, 622, 472);
  else {
    const focus = rounded(screen, "Tablet V2 focus", 476, 178, 598, 448, C.surface, 26, C.ink);
    focus.opacity = 0.5;
    circle(screen, "Tablet camera icon", 706, 334, 136, C.v2Sky);
    addIcon(screen, "camera", 752, 380, 44);
  }
  rounded(screen, "Tablet camera primary", 760, 708, 360, 64, confirm ? C.v2Coral : C.yellow500, 28);
  makeText(screen, confirm ? "이 그림 쓰기" : "사진 찍기", 784, 727, 312, 18, "extraBold", C.ink, "CENTER");
}

function renderTabletGalleryV2(screen) {
  rounded(screen, "Tablet V2 gallery wall", 0, 0, 1194, 834, "#F8DCA6", 0);
  addTabletV2TopBar(screen, "C12", "나의 그림 전시회");
  imageRect(screen, "Tablet gallery Dodami", IMAGES.brand, 24, 552, 244, 232);
  const items = [
    ["초록 숲", C.v2Aqua],
    ["우리 가족", C.v2Coral],
    ["비 오는 날", C.v2Sky],
    ["우주 여행", C.v2Purple],
    ["커다란 고래", C.v2Sky],
    ["우리 집", C.yellow500],
  ];
  items.forEach(([label, color], index) => {
    const col = index % 3;
    const row = Math.floor(index / 3);
    const x = 282 + col * 292;
    const y = 132 + row * 324;
    rounded(screen, `Tablet V2 frame shadow ${label}`, x + 7, y + 8, 258, 270, "#9F6C3E", 14);
    rounded(screen, `Tablet V2 frame ${label}`, x, y, 258, 270, "#C68A4B", 14);
    rounded(screen, `${label} tablet art`, x + 18, y + 18, 222, 194, color, 9);
    makeText(screen, label, x + 18, y + 226, 222, 18, "extraBold", C.v2Cream, "CENTER");
  });
}

function renderTabletSupportV2(screen, kind) {
  addSceneBackdrop(screen, 1194, 834, kind === "exit" ? C.v2Sun : C.v2Aqua, C.v2Leaf);
  addTabletV2TopBar(screen, kind === "exit" ? "C14" : "C13", kind === "exit" ? "집으로 가기" : "도다미 도움");
  imageRect(screen, "Tablet support Dodami", IMAGES.brand, 94, 150, 420, 396);
  rounded(screen, "Tablet support cloud", 70, 546, 460, 142, C.surface, 46);
  makeText(screen, kind === "exit" ? "활동을 마치고 집으로 갈까?" : "무엇이 어려운지 알려줘!", 104, 592, 392, 26, "extraBold", C.ink, "CENTER");
  if (kind === "exit") {
    circle(screen, "Tablet V2 hold shadow", 716, 218, 286, C.v2Shadow);
    circle(screen, "Tablet V2 hold", 716, 204, 286, C.v2Coral, C.surface);
    circle(screen, "Tablet V2 hold inner", 766, 254, 186, C.yellow500);
    addIcon(screen, "home", 847, 319, 24);
    makeText(screen, "3초 동안 꾹", 786, 376, 146, 20, "extraBold", C.ink, "CENTER");
  } else {
    addTactileTile(screen, "Tablet V2 help draw", 620, 182, 480, 180, C.v2Coral, "그림이 잘 안 그려져요", "draw");
    addTactileTile(screen, "Tablet V2 help sound", 620, 408, 480, 180, C.v2Sky, "도다미 목소리가 안 들려요", "help");
    rounded(screen, "Tablet guardian help", 620, 650, 480, 64, C.yellow500, 28);
    makeText(screen, "보호자와 함께 보기", 644, 669, 432, 18, "extraBold", C.ink, "CENTER");
  }
}

function createTabletScreenV2(code, title, kind) {
  const screen = makeFrame(`${code} · ${title} · Tablet V2`, 1194, 834, C.v2Sun);
  screen.cornerRadius = 28;
  if (kind === "home") renderTabletHomeV2(screen);
  else if (kind === "mode") renderTabletTopicV2(screen);
  else if (kind === "tutorial") renderTabletTutorialV2(screen);
  else if (kind === "drawing") renderTabletDrawingV2(screen, false);
  else if (kind === "upload") renderTabletCameraV2(screen, false);
  else if (kind === "confirm") renderTabletCameraV2(screen, true);
  else if (kind === "uploadDialogue") renderTabletDrawingV2(screen, true);
  else if (kind === "emotion") renderTabletEmotionV2(screen);
  else if (kind === "complete") renderTabletCompleteV2(screen);
  else if (kind === "history") renderTabletGalleryV2(screen);
  else renderTabletSupportV2(screen, kind);
  return screen;
}

function createScreensPage(page, screens, tablet = false) {
  const columns = tablet ? 2 : 4;
  const gapX = tablet ? 80 : 64;
  const gapY = tablet ? 96 : 80;
  const width = tablet ? 1194 : 390;
  const height = tablet ? 834 : 844;

  screens.forEach(([code, title, kind], index) => {
    const screen = tablet
      ? createTabletScreenV2(code, title, kind)
      : createMobileScreenV2(code, title, kind);
    screen.x = (index % columns) * (width + gapX);
    screen.y = Math.floor(index / columns) * (height + gapY);
    page.appendChild(screen);
  });
}

function createSectionBoard(page, name, x, y, width, height, buildContent) {
  const section = figma.createSection();
  section.name = name;
  section.x = x;
  section.y = y;
  section.resizeWithoutConstraints(width, height);
  section.setPluginData(GENERATED_NODE_KEY, "true");
  page.appendChild(section);

  buildContent(section);
  section.children.forEach((child) => {
    child.x += 80;
    child.y += 80;
  });
  return section;
}

function createHandoffPage(page) {
  const board = makeFrame("Handoff", 1800, 1200, C.canvas);
  page.appendChild(board);
  makeText(board, "99 · Handoff", 72, 64, 700, 40, "extraBold");
  makeText(board, "아동 화면 전용 · 보호자 화면은 별도 디자인 시스템으로 분리", 72, 118, 900, 18, "regular", C.inkMuted);

  const flow = [
    ["01", "시작"],
    ["02", "프로필"],
    ["03", "홈"],
    ["04", "활동 선택"],
    ["05–09", "그림·대화"],
    ["10", "마음 선택"],
    ["11", "완료"],
  ];
  flow.forEach(([code, label], index) => {
    const x = 72 + index * 236;
    rounded(board, `Flow ${code}`, x, 226, 196, 112, index === 6 ? C.yellow500 : C.surface, 24, C.border);
    makeText(board, code, x + 18, 244, 160, 13, "bold", C.inkMuted, "CENTER");
    makeText(board, label, x + 18, 280, 160, 18, "extraBold", C.ink, "CENTER");
    if (index < flow.length - 1) {
      const arrow = figma.createLine();
      arrow.x = x + 198;
      arrow.y = 282;
      arrow.resize(36, 0);
      arrow.strokes = [solid(C.borderStrong)];
      arrow.strokeWeight = 2;
      arrow.strokeCap = "ARROW_LINES";
      board.appendChild(arrow);
    }
  });

  const notes = [
    ["Primary", "#F2D765", "시작·선택·완료"],
    ["Font", "NanumSquare Neo", "Regular / Bold / ExtraBold"],
    ["Touch", "48–64px", "핵심 행동은 60px 이상"],
    ["Radius", "16–24px", "카드 24px, 버튼 20px"],
    ["Mascot", "Dodami", "안내·질문·칭찬 역할"],
    ["Safety", "Guardian gate", "나가기는 3초 길게 누르기"],
  ];
  notes.forEach(([title, value, description], index) => {
    const col = index % 3;
    const row = Math.floor(index / 3);
    const x = 72 + col * 550;
    const y = 452 + row * 250;
    rounded(board, `Handoff / ${title}`, x, y, 500, 208, C.surface, 28, C.border);
    makeText(board, title, x + 28, y + 28, 440, 14, "bold", C.inkMuted);
    makeText(board, value, x + 28, y + 70, 440, 26, "extraBold");
    makeText(board, description, x + 28, y + 124, 440, 16, "regular", C.inkMuted);
  });
}

function createV2FlowSection(page) {
  const board = makeFrame("Dodam Child UI v2 / Flow", 1900, 1280, C.v2Sun);
  page.appendChild(board);
  addSceneBackdrop(board, 1900, 1280, C.v2Sun, C.v2Aqua);
  makeText(board, "99 · V2 Child Journey", 72, 56, 900, 42, "extraBold");
  makeText(board, "도다미가 시작부터 칭찬까지 같은 친구로 이어주는 흐름", 72, 116, 980, 20, "bold", C.inkMuted);
  const flow = [
    ["01", "만나기", C.yellow500, "home"],
    ["02", "친구 고르기", C.v2Aqua, "check"],
    ["03", "놀이방", C.v2Coral, "home"],
    ["04", "주제 고르기", C.v2Purple, "draw"],
    ["05–09", "그리고 말하기", C.v2Sky, "mic"],
    ["10", "마음 고르기", C.v2Aqua, "check"],
    ["11", "칭찬과 완료", C.v2Coral, "home"],
  ];
  flow.forEach(([code, label, color, icon], index) => {
    const x = 62 + index * 260;
    addTactileTile(board, `V2 flow ${code}`, x, 246, 222, 190, color, label, icon);
    rounded(board, `V2 flow code ${code}`, x + 18, 208, 82, 42, C.surface, 21);
    makeText(board, code, x + 28, 218, 62, 14, "extraBold", C.ink, "CENTER");
    if (index < flow.length - 1) {
      makeText(board, "→", x + 224, 320, 36, 28, "extraBold", C.ink, "CENTER");
    }
  });
  rounded(board, "V2 flow drawing focus", 82, 574, 1736, 520, C.surface, 42);
  imageRect(board, "V2 flow Dodami", IMAGES.drawing, 120, 620, 470, 410);
  addV2PaperStage(board, 650, 630, 660, 360, "V2 flow sketchbook");
  addDoodle(board, 678, 654, 604, 310);
  rounded(board, "V2 flow conversation", 1360, 652, 390, 216, C.v2Sun, 40);
  makeText(board, "그림이 먼저,\n도구는 가까이,\n도다미 질문은 옆에.", 1400, 700, 310, 26, "extraBold", C.ink, "CENTER", 38);
  addCrayonTray(board, 1360, 902, 390, true);
}

async function preparePage() {
  await figma.loadAllPagesAsync();
  const pages = figma.root.children.slice();
  const generatedNames = [...GENERATED_PAGES, ...LEGACY_GENERATED_PAGES];
  const generatedPages = pages.filter((page) => generatedNames.includes(page.name));
  const target = generatedPages[0] || figma.currentPage || pages[0];

  await target.loadAsync();
  await figma.setCurrentPageAsync(target);

  const targetWasGenerated = generatedNames.includes(target.name);
  if (targetWasGenerated) {
    target.children.slice().forEach((node) => node.remove());
    target.name = GENERATED_PAGES[0];
  } else {
    target.children
      .filter((node) => node.getPluginData(GENERATED_NODE_KEY) === "true")
      .forEach((node) => node.remove());
    if (target.children.length === 0) target.name = GENERATED_PAGES[0];
  }

  for (const page of generatedPages.slice(1)) {
    await page.loadAsync();
    page.remove();
  }
  return target;
}

async function generate() {
  figma.ui.postMessage({ type: "progress", message: "폰트를 불러오고 있어요…" });
  const fontResult = await loadFonts();
  if (fontResult.usingFallback) {
    throw new Error(
      "NanumSquare Neo가 Figma에 보이지 않습니다. Figma를 완전히 종료한 뒤 폰트 설치 후 다시 실행해 주세요.",
    );
  }

  figma.ui.postMessage({ type: "progress", message: "도다미 자산과 디자인 토큰을 준비하고 있어요…" });
  IMAGES = {
    brand: figma.createImage(base64Bytes(DODAMI_BRAND_BASE64)).hash,
    drawing: figma.createImage(base64Bytes(DODAMI_DRAWING_BASE64)).hash,
  };

  await ensureVariables();
  await ensureTextStyles();

  figma.ui.postMessage({ type: "progress", message: "한 페이지 안에 디자인 섹션을 만들고 있어요…" });
  const page = await preparePage();

  const cover = createSectionBoard(page, "00 · V2 Direction", 0, 0, 1760, 1260, createV2DirectionSection);
  createSectionBoard(page, "01 · V2 Foundations", 1880, 0, 2060, 1760, createV2FoundationsSection);
  createSectionBoard(page, "02 · V2 Components", 0, 1380, 2260, 1960, createV2ComponentsSection);

  figma.ui.postMessage({ type: "progress", message: "모바일 C01–C14 화면을 만들고 있어요…" });
  createSectionBoard(page, "10 · V2 Mobile", 4660, 0, 1912, 3776, (section) => {
    createScreensPage(section, MOBILE_SCREENS, false);
  });

  figma.ui.postMessage({ type: "progress", message: "태블릿 C03–C14 화면을 만들고 있어요…" });
  createSectionBoard(page, "11 · V2 Tablet", 6692, 0, 2628, 5644, (section) => {
    createScreensPage(section, TABLET_SCREENS, true);
  });
  createSectionBoard(page, "99 · V2 Flow", 2380, 1940, 2060, 1440, createV2FlowSection);

  figma.currentPage.selection = [cover];
  figma.viewport.scrollAndZoomIntoView([cover]);

  figma.ui.postMessage({
    type: "complete",
    pages: GENERATED_PAGES.length,
    screens: MOBILE_SCREENS.length + TABLET_SCREENS.length,
  });
  figma.notify("도담 아동 UI 26개 화면을 만들었어요.", { timeout: 4000 });
}

figma.showUI(__html__, { width: 360, height: 250, themeColors: true });

figma.ui.onmessage = async (message) => {
  if (message.type !== "generate") return;
  try {
    await generate();
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    figma.ui.postMessage({ type: "error", message: detail });
    figma.notify(`생성 중 오류: ${detail}`, { error: true, timeout: 6000 });
  }
};

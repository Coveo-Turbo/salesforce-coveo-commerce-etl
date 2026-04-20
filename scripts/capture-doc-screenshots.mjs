import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const docsImageDir = path.join(repoRoot, "docs", "images");
const outputDir = path.join(repoRoot, "output", "playwright");
const targetOrg = process.env.TARGET_ORG || "ccetl";

fs.mkdirSync(docsImageDir, { recursive: true });
fs.mkdirSync(outputDir, { recursive: true });

const viewport = { width: 1600, height: 2200 };

function getFrontdoorUrl(lightningPath) {
  const output = execSync(
    `sf org open -o ${targetOrg} -r --path '${lightningPath}'`,
    { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  );
  return output
    .trim()
    .split("\n")
    .find((line) => line.includes("URL: "))
    ?.replace(/^.*URL:\s*/, "");
}

function clipFromBox(box, options = {}) {
  const paddingLeft = options.paddingLeft ?? 24;
  const paddingRight = options.paddingRight ?? 24;
  const paddingTop = options.paddingTop ?? 28;
  const paddingBottom = options.paddingBottom ?? 28;

  const x = Math.max(0, Math.floor(box.x - paddingLeft));
  const y = Math.max(0, Math.floor(box.y - paddingTop));
  const maxWidth = viewport.width - x - 8;
  const maxHeight = viewport.height - y - 8;

  const width = Math.min(
    maxWidth,
    Math.ceil(options.width ?? box.width + paddingLeft + paddingRight)
  );
  const height = Math.min(
    maxHeight,
    Math.ceil(options.height ?? box.height + paddingTop + paddingBottom)
  );

  return { x, y, width, height };
}

async function openOrgPage(browser, lightningPath, waitForText) {
  const page = await browser.newPage({ viewport });
  const frontdoorUrl = getFrontdoorUrl(lightningPath);
  if (!frontdoorUrl) {
    throw new Error(`Unable to resolve a frontdoor URL for ${lightningPath}`);
  }

  await page.goto(frontdoorUrl, { waitUntil: "domcontentloaded" });
  await page
    .waitForLoadState("networkidle", { timeout: 20000 })
    .catch(() => {});
  if (waitForText) {
    await page
      .locator(`text=${waitForText}`)
      .first()
      .waitFor({ timeout: 45000 });
  }
  await page.waitForTimeout(2500);
  return page;
}

async function captureClip(page, targetLocator, outputPath, options = {}) {
  const locator = targetLocator.first();
  await locator.waitFor({ timeout: 45000 });
  let box = await locator.boundingBox();
  if (!box) {
    throw new Error(`Unable to capture ${outputPath}: locator has no box.`);
  }

  const desiredTop = options.desiredTop ?? 120;
  if (box.y > desiredTop) {
    const scrollY = await page.evaluate(() => window.scrollY);
    await page.evaluate(({ nextScrollY }) => window.scrollTo(0, nextScrollY), {
      nextScrollY: Math.max(0, Math.floor(scrollY + box.y - desiredTop))
    });
    await page.waitForTimeout(options.waitAfterScrollMs ?? 700);
    box = await locator.boundingBox();
  }

  if (!box) {
    throw new Error(`Unable to capture ${outputPath}: locator lost its box.`);
  }

  await page.screenshot({
    path: outputPath,
    clip: clipFromBox(box, options)
  });
}

async function captureSetupScreens(browser) {
  const page = await openOrgPage(
    browser,
    "/lightning/n/Coveo_ETL_Setup",
    "Coveo Commerce ETL Setup"
  );

  await captureClip(
    page,
    page.locator("text=Manage catalog job configurations"),
    path.join(docsImageDir, "setup-catalog-jobs.png"),
    {
      paddingLeft: 36,
      paddingTop: 44,
      width: 1220,
      height: 960
    }
  );

  await page.getByRole("button", { name: "Use as Draft" }).nth(2).click();
  await page.waitForTimeout(4500);

  await captureClip(
    page,
    page.locator("text=GUIDED JOB DRAFT"),
    path.join(docsImageDir, "setup-guided-job-draft.png"),
    {
      paddingLeft: 18,
      paddingTop: 28,
      width: 1260,
      height: 1260,
      desiredTop: 70
    }
  );

  const schedulingButton = page
    .getByRole("button", { name: /Scheduling/i })
    .first();
  await schedulingButton.scrollIntoViewIfNeeded();
  await page.waitForTimeout(400);
  const ariaExpanded = await schedulingButton.getAttribute("aria-expanded");
  if (ariaExpanded !== "true") {
    await schedulingButton.click();
    await page.waitForTimeout(800);
  }

  await captureClip(
    page,
    page.locator("text=SELECTED CONFIG"),
    path.join(docsImageDir, "setup-scheduling-panel.png"),
    {
      paddingLeft: 18,
      paddingTop: 28,
      width: 1260,
      height: 980,
      desiredTop: 80
    }
  );

  await page.close();
}

async function captureRunCenterScreens(browser) {
  const page = await openOrgPage(
    browser,
    "/lightning/n/Catalog_Job_Console",
    "Catalog Sync Run Center"
  );

  await captureClip(
    page,
    page.locator("text=Choose a sync configuration"),
    path.join(docsImageDir, "run-center-job-inventory.png"),
    {
      paddingLeft: 32,
      paddingTop: 90,
      width: 1530,
      height: 930,
      desiredTop: 70
    }
  );

  const runDeltaButton = page.getByRole("button", {
    name: "Run Delta Products"
  });
  await runDeltaButton.scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  await runDeltaButton.click();
  await page.waitForTimeout(2500);

  await captureClip(
    page,
    page.locator("text=SELECTED CONFIG"),
    path.join(docsImageDir, "run-center-live-runs.png"),
    {
      paddingLeft: 24,
      paddingTop: 34,
      width: 1530,
      height: 1120,
      desiredTop: 70
    }
  );

  await page.close();
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    await captureSetupScreens(browser);
    await captureRunCenterScreens(browser);
    console.log("Saved screenshots to", docsImageDir);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

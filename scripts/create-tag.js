#!/usr/bin/env node
// Creates and pushes a git tag for the current package.json version.
// Idempotent: exits cleanly if the tag already exists.
const { execSync } = require('child_process');
const path = require('path');

const { version } = require(path.join(__dirname, '..', 'package.json'));
const tag = `v${version}`;

const existing = execSync('git tag').toString().trim().split('\n');
if (existing.includes(tag)) {
  console.log(`Tag ${tag} already exists — nothing to do.`);
  process.exit(0);
}

execSync(`git tag ${tag}`, { stdio: 'inherit' });
execSync(`git push origin ${tag}`, { stdio: 'inherit' });
console.log(`Created and pushed tag ${tag}`);

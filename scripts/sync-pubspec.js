#!/usr/bin/env node
// Reads the version from package.json and writes it to pubspec.yaml,
// incrementing the Flutter build number by 1.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const { version } = require(path.join(root, 'package.json'));

const pubspecPath = path.join(root, 'pubspec.yaml');
const pubspec = fs.readFileSync(pubspecPath, 'utf8');

const match = pubspec.match(/^version:\s*[\d.]+\+(\d+)/m);
const buildNumber = match ? parseInt(match[1], 10) + 1 : 1;
const updated = pubspec.replace(/^version:.*$/m, `version: ${version}+${buildNumber}`);

fs.writeFileSync(pubspecPath, updated);
console.log(`pubspec.yaml updated to ${version}+${buildNumber}`);

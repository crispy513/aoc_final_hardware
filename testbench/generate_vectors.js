const fs = require("fs");
const path = require("path");

const P = 4;
const F = 32;
const Q = 4;
const S = 3;

function packBytes(values) {
  let word = 0;
  values.forEach((value, index) => {
    word |= (value & 0xff) << (8 * index);
  });
  return word >>> 0;
}

function toS8(value) {
  value &= 0xff;
  return value >= 128 ? value - 256 : value;
}

function toU32(value) {
  return value >>> 0;
}

function hex32(value) {
  return (value >>> 0).toString(16).padStart(8, "0");
}

const ifmap = [];
for (let x = 0; x < F + S - 1; x += 1) {
  const channels = [];
  for (let c = 0; c < Q; c += 1) {
    const signedValue = ((x * 5 + c * 17 + Math.floor(x / 3) * 9) % 97) - 48;
    channels.push(signedValue + 128);
  }
  ifmap.push(packBytes(channels));
}

const filterWords = [];
for (let p = 0; p < P; p += 1) {
  for (let s = 0; s < S; s += 1) {
    const channels = [];
    for (let c = 0; c < Q; c += 1) {
      let value = ((p * 11 + s * 7 + c * 5) % 17) - 8;
      if ((p + s + c) % 5 === 0) {
        value = 0;
      }
      channels.push(value & 0xff);
    }
    filterWords.push(packBytes(channels));
  }
}

const ipsum = [];
for (let x = 0; x < F; x += 1) {
  for (let p = 0; p < P; p += 1) {
    let value = ((x * 13 + p * 19) % 71) - 35;
    if ((x + p) % 9 === 0) {
      value = 0;
    }
    ipsum.push(toU32(value));
  }
}

const golden = [];
for (let x = 0; x < F; x += 1) {
  for (let p = 0; p < P; p += 1) {
    const rawIpsum = ipsum[x * P + p];
    let acc = rawIpsum & 0x80000000 ? rawIpsum - 0x100000000 : rawIpsum;

    for (let s = 0; s < S; s += 1) {
      const ifmapWord = ifmap[x + s];
      const filterWord = filterWords[p * S + s];
      for (let c = 0; c < Q; c += 1) {
        const ifmapU8 = (ifmapWord >>> (8 * c)) & 0xff;
        const filterU8 = (filterWord >>> (8 * c)) & 0xff;
        acc += (ifmapU8 - 128) * toS8(filterU8);
      }
    }
    golden.push(toU32(acc));
  }
}

const outDir = __dirname;
const inputLines = [
  `${P} ${F} ${Q}`,
  `${ifmap.length}`,
  ...ifmap.map(hex32),
  `${filterWords.length}`,
  ...filterWords.map(hex32),
  `${ipsum.length}`,
  ...ipsum.map(hex32),
];

const goldenLines = [`${golden.length}`, ...golden.map(hex32)];

fs.writeFileSync(path.join(outDir, "input.txt"), `${inputLines.join("\n")}\n`, "ascii");
fs.writeFileSync(path.join(outDir, "golden.txt"), `${goldenLines.join("\n")}\n`, "ascii");

console.log(`Wrote input.txt and golden.txt with ${golden.length} golden outputs`);

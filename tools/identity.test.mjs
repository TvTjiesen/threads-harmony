import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../app/entry/src/main/ets/model/LocalIdentity.ets', import.meta.url), 'utf8');
const modelUrl = `data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`;
const { decodeIdentity, emptyIdentity, identityLength, normalizeIdentity, IDENTITY_NAME_LIMIT, IDENTITY_BIO_LIMIT } =
  await import(modelUrl);

const empty = { name: '你', bio: '' };

test('defaults are independent and an absent bio is valid', () => {
  assert.deepEqual(emptyIdentity(), empty);
  assert.notEqual(emptyIdentity(), emptyIdentity());
  assert.deepEqual(normalizeIdentity('  林小满  ', ' \n '), { name: '林小满', bio: '' });
  assert.equal(normalizeIdentity('　\t\n', '简介'), undefined);
});

test('valid fields trim at boundaries and retain intentional multi-line bio text', () => {
  const normalized = { name: '林小满', bio: '记一些日常\n\n还有散步。' };
  assert.deepEqual(normalizeIdentity('  林小满  ', '  记一些日常\r\n\r还有散步。  '), normalized);
  assert.deepEqual(decodeIdentity(JSON.stringify(normalized)), normalized);
  assert.deepEqual(decodeIdentity('{"name":"  小满  ","bio":" 日常 "}'), { name: '小满', bio: '日常' });
});

test('display limits count Unicode code points without splitting supplementary characters', () => {
  const name = '🙂'.repeat(IDENTITY_NAME_LIMIT);
  const bio = '🎧'.repeat(IDENTITY_BIO_LIMIT);
  assert.equal(identityLength(name), IDENTITY_NAME_LIMIT);
  assert.equal(identityLength(`你${name}`), IDENTITY_NAME_LIMIT + 1);
  assert.deepEqual(normalizeIdentity(name, bio), { name, bio });
  assert.equal(normalizeIdentity(`${name}啊`, ''), undefined);
  assert.equal(normalizeIdentity('你', `${bio}。`), undefined);
});

test('missing, corrupt and invalid snapshots safely fall back to the default identity', () => {
  const invalid = [
    '', '{"name":', 'null', '[]', '7', '"你"', '{}', '{"name":"你"}', '{"name":"你","bio":true}',
    '{"name":null,"bio":""}', '{"name":"a\\nb","bio":""}', '{"name":"a\\u2028b","bio":""}',
    '{"name":"你","bio":"a\\u0000b"}', '{"name":"a\\ud83db","bio":""}', '{"name":"你","bio":"\\udd1e"}',
    JSON.stringify({ name: '你', bio: 'x'.repeat(5000) })
  ];
  for (const input of invalid) {
    assert.deepEqual(decodeIdentity(input), empty);
  }
});

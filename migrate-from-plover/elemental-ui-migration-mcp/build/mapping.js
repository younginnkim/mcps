import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const json = readFileSync(join(here, 'mapping.json'), 'utf-8');
export const widgetMapping = JSON.parse(json);
export function widgetsByAction(action) {
    return Object.fromEntries(Object.entries(widgetMapping).filter(([, m]) => m.action === action));
}

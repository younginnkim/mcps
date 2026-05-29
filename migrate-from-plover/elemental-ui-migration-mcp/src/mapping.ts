import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export type MigrationAction = 'rename' | 'rewrite-params' | 'restructure' | 'manual';

export interface WidgetMapping {
  target: string;
  action: MigrationAction;
  deprecated?: boolean;
  deprecatedNote?: string;
  breakingChange?: boolean;
  notes?: string;
  paramChanges?: {
    removed?: string[];
    renamed?: Record<string, string>;
    added?: string[];
    notes?: string;
  };
}

const here = dirname(fileURLToPath(import.meta.url));
const json = readFileSync(join(here, 'mapping.json'), 'utf-8');

export const widgetMapping: Record<string, WidgetMapping> = JSON.parse(json);

export function widgetsByAction(action: MigrationAction): Record<string, WidgetMapping> {
  return Object.fromEntries(
    Object.entries(widgetMapping).filter(([, m]) => m.action === action),
  );
}

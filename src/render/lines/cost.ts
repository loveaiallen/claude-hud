import type { RenderContext } from '../../types.js';
import { formatUsd } from '../../cost.js';
import { t } from '../../i18n/index.js';
import { label } from '../colors.js';

export function renderCostEstimate(ctx: RenderContext): string | null {
  if (ctx.config?.display?.showCost !== true) {
    return null;
  }

  if (ctx.costUsd === null) {
    return null;
  }

  return label(`${t('label.cost')} ${formatUsd(ctx.costUsd)}`, ctx.config?.colors);
}

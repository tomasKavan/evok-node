/**
 * This package's own npm name.
 *
 * A placeholder so the package has a real export, a real declaration and a
 * resolvable entrypoint before any implementation lands. Delete it with the
 * first real export.
 */
export const packageName: string = '@evok-node/rig';

// SCRATCH: T0.3 verification, reverted in the next commit.
import { packageName as coreName } from '@evok-node/core';
export const scratchUsesCore: string = coreName;

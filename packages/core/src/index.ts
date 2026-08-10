/**
 * This package's own npm name.
 *
 * A placeholder so the package has a real export, a real declaration and a
 * resolvable entrypoint before any implementation lands. Delete it with the
 * first real export.
 */
export const packageName: string = '@evok-node/core';

// SCRATCH: T0.3 verification, reverted in the next commit.
import { packageName as serverName } from '@evok-node/server';
export const scratchUsesServer: string = serverName;

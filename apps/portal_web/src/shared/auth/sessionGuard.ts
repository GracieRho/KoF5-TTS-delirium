export function shouldClearSession(currentToken: string | null, requestToken: string) {
  return currentToken === requestToken
}

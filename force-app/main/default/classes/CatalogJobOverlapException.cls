/**
 * Signals that a product run already owns the resolved export target.
 * Interactive launches surface this to the user; schedulers treat it as an
 * expected skip so overlapping schedules do not produce unhandled job errors.
 */
public class CatalogJobOverlapException extends CatalogJobConfigException {
}

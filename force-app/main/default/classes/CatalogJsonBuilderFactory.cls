/**
 * Factory class for creating ICatalogJsonBuilder instances.
 *
 * Supports two modes of operation:
 * 1. Global default: Uses the 'Active' CatalogJsonBuilderMapping__mdt record
 * 2. Per-catalog: Uses the BuilderType__c field from CatalogJobConfig__mdt
 *
 * Builder Type Options:
 * - Default: Simple product exports without grouping/variant logic
 * - Commerce: Standard commerce builder with category hierarchy
 * - Grouping: Product grouping/family relationships
 * - Variant: Product variant (SKU-level) relationships
 * - GroupingWithVariants: Combined grouping and variant support
 *
 * @see https://docs.coveo.com/en/m53g0506/coveo-for-commerce/catalog-variant-data-and-product-groupings
 */
public with sharing class CatalogJsonBuilderFactory {
  // Mapping of builder type names to class names
  private static final Map<String, String> BUILDER_TYPE_MAP = new Map<String, String>{
    'default' => 'CatalogJsonBuilderDefault',
    'commerce' => 'CatalogJsonBuilderCommerce',
    'grouping' => 'CatalogJsonBuilderGrouping',
    'variant' => 'CatalogJsonBuilderVariant',
    'groupingwithvariants' => 'CatalogJsonBuilderGroupingWithVariants'
  };
  @TestVisible private static String cachedGlobalBuilderClassName;

  /**
   * Returns the globally configured builder instance.
   * Uses the 'Active' CatalogJsonBuilderMapping__mdt record to determine which builder to use.
   *
   * @return ICatalogJsonBuilder instance
   */
  public static ICatalogJsonBuilder get() {
    return createBuilder(resolveBuilderClassName(null));
  }

  /**
   * Returns a builder instance based on the builder type specified in the catalog config.
   * Falls back to the global default if no builder type is specified.
   *
   * @param builderType The builder type name (e.g., 'Default', 'Grouping', 'Variant')
   * @return ICatalogJsonBuilder instance
   */
  public static ICatalogJsonBuilder getForBuilderType(String builderType) {
    return createBuilder(resolveBuilderClassName(builderType));
  }

  public static String resolveBuilderClassName(String builderType) {
    if (String.isBlank(builderType)) {
      if (String.isNotBlank(cachedGlobalBuilderClassName)) {
        return cachedGlobalBuilderClassName;
      }

      try {
        CatalogJsonBuilderMapping__mdt mapping = [
          SELECT ClassName__c
          FROM CatalogJsonBuilderMapping__mdt
          WHERE DeveloperName = 'Active'
          LIMIT 1
        ];
        cachedGlobalBuilderClassName = String.isNotBlank(mapping.ClassName__c)
          ? mapping.ClassName__c
          : 'CatalogJsonBuilderCommerce';
      } catch (Exception e) {
        cachedGlobalBuilderClassName = 'CatalogJsonBuilderCommerce';
      }

      return cachedGlobalBuilderClassName;
    }

    String normalizedType = builderType.trim().toLowerCase();
    if (BUILDER_TYPE_MAP.containsKey(normalizedType)) {
      return BUILDER_TYPE_MAP.get(normalizedType);
    }

    return builderType.trim();
  }

  /**
   * Returns all available builder type options for UI display.
   *
   * @return List of maps containing 'value' and 'label' for each builder type
   */
  public static List<Map<String, String>> getAvailableBuilderTypes() {
    List<Map<String, String>> options = new List<Map<String, String>>();

    options.add(
      new Map<String, String>{
        'value' => 'Default',
        'label' => 'Default - Simple products without grouping/variant logic'
      }
    );
    options.add(
      new Map<String, String>{
        'value' => 'Commerce',
        'label' => 'Commerce - Standard with category hierarchy (default)'
      }
    );
    options.add(
      new Map<String, String>{
        'value' => 'Grouping',
        'label' => 'Grouping - Product families with parent-child relationships'
      }
    );
    options.add(
      new Map<String, String>{
        'value' => 'Variant',
        'label' => 'Variant - Product variants (size, color, etc.)'
      }
    );
    options.add(
      new Map<String, String>{
        'value' => 'GroupingWithVariants',
        'label' => 'GroupingWithVariants - Combined grouping and variant support'
      }
    );

    return options;
  }

  /**
   * Creates a builder instance from a class name.
   *
   * @param className The fully qualified Apex class name
   * @return ICatalogJsonBuilder instance
   * @throws AuraHandledException if the class cannot be found or instantiated
   */
  private static ICatalogJsonBuilder createBuilder(String className) {
    if (String.isBlank(className)) {
      className = 'CatalogJsonBuilderCommerce';
    }

    Type t = Type.forName(className);
    if (t == null) {
      throw new AuraHandledException('Unknown builder class: ' + className);
    }
    return (ICatalogJsonBuilder) t.newInstance();
  }
}

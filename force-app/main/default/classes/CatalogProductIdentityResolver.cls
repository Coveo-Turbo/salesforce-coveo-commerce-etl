public with sharing class CatalogProductIdentityResolver {
  public static ICatalogJsonBuilder getBuilder(CatalogJobConfig__mdt jobConfig) {
    return getBuilder(jobConfig == null ? null : jobConfig.BuilderType__c);
  }

  public static ICatalogJsonBuilder getBuilder(String builderType) {
    return CatalogJsonBuilderFactory.getForBuilderType(builderType);
  }

  public static Boolean supportsBuilderDrivenIdentity(
    CatalogJobConfig__mdt jobConfig
  ) {
    return supportsBuilderDrivenIdentity(
      jobConfig == null ? null : jobConfig.BuilderType__c
    );
  }

  public static Boolean supportsBuilderDrivenIdentity(String builderType) {
    return supportsBuilderDrivenIdentity(getBuilder(builderType));
  }

  public static Boolean supportsBuilderDrivenIdentity(
    ICatalogJsonBuilder builder
  ) {
    return builder instanceof ICatalogProductIdentityProvider;
  }

  public static List<String> getRequiredProductFields(
    CatalogJobConfig__mdt jobConfig
  ) {
    return getRequiredProductFields(getBuilder(jobConfig));
  }

  public static List<String> getRequiredProductFields(String builderType) {
    return getRequiredProductFields(getBuilder(builderType));
  }

  public static List<String> getRequiredProductFields(ICatalogJsonBuilder builder) {
    List<String> fields = new List<String>{ 'Id' };

    if (builder instanceof ICatalogProductIdentityProvider) {
      ICatalogProductIdentityProvider provider =
        (ICatalogProductIdentityProvider) builder;
      List<String> providerFields = provider.getRequiredProductFieldsForIdentity();
      if (providerFields == null) {
        return fields;
      }
      for (String fieldName : providerFields) {
        addFieldIfMissing(fields, fieldName);
      }
      return fields;
    }

    addFieldIfMissing(fields, 'ProductCode');
    return fields;
  }

  public static Map<Id, String> resolveEcProductIds(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products
  ) {
    return resolveEcProductIds(getBuilder(jobConfig), products);
  }

  public static Map<Id, String> resolveEcProductIds(
    String builderType,
    List<Product2> products
  ) {
    return resolveEcProductIds(getBuilder(builderType), products);
  }

  public static Map<Id, String> resolveEcProductIds(
    ICatalogJsonBuilder builder,
    List<Product2> products
  ) {
    Map<Id, String> resolvedIds = new Map<Id, String>();

    if (products == null || products.isEmpty()) {
      return resolvedIds;
    }

    if (builder instanceof ICatalogProductIdentityProvider) {
      ICatalogProductIdentityProvider provider =
        (ICatalogProductIdentityProvider) builder;
      Map<Id, String> providerIds = provider.resolveEcProductIds(products);

      for (Product2 product : products) {
        if (product == null || product.Id == null) {
          throw new CatalogJobException(
            'Identity resolution requires every product to include an Id.'
          );
        }

        if (providerIds == null || !providerIds.containsKey(product.Id)) {
          throw new CatalogJobException(
            'Identity provider did not return an ec_product_id for product ' +
            product.Id +
            '.'
          );
        }

        String ecProductId = providerIds.get(product.Id);
        if (String.isBlank(ecProductId)) {
          throw new CatalogJobException(
            'Identity provider returned a blank ec_product_id for product ' +
            product.Id +
            '.'
          );
        }

        resolvedIds.put(product.Id, ecProductId);
      }

      return resolvedIds;
    }

    return resolveFallbackEcProductIds(products);
  }

  public static Map<Id, String> resolveFallbackEcProductIds(
    List<Product2> products
  ) {
    Map<Id, String> resolvedIds = new Map<Id, String>();

    if (products == null) {
      return resolvedIds;
    }

    for (Product2 product : products) {
      if (product == null || product.Id == null) {
        throw new CatalogJobException(
          'Fallback identity resolution requires every product to include an Id.'
        );
      }

      resolvedIds.put(product.Id, resolveFallbackEcProductId(product));
    }

    return resolvedIds;
  }

  public static String resolveFallbackEcProductId(Product2 product) {
    return String.isNotBlank(product.ProductCode)
      ? product.ProductCode
      : String.valueOf(product.Id);
  }

  private static void addFieldIfMissing(List<String> fields, String fieldName) {
    if (String.isBlank(fieldName)) {
      return;
    }

    String trimmed = fieldName.trim();
    if (String.isNotBlank(trimmed) && !fields.contains(trimmed)) {
      fields.add(trimmed);
    }
  }
}

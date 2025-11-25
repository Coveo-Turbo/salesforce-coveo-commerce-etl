public virtual with sharing class CatalogJsonBuilderDefault implements ICatalogJsonBuilder {
    public virtual String buildFullUpdateNdjson(List<Product2> products, Map<Id, PricebookEntry> pbesByProduct) {
        List<Object> updateArr = new List<Object>();
        for (Product2 p : products) {
            Map<String, Object> fields = new Map<String, Object>();
            fields.put('ec_brand', p.Brand__c);
            fields.put('ec_price', pbesByProduct.containsKey(p.Id) ? pbesByProduct.get(p.Id).UnitPrice : null);
            fields.put('ec_category', buildCategoryPathList(p.Id));
            fields.put('ec_images', p.Image_URL__c != null ? new List<String>{p.Image_URL__c} : null);
            fields.put('ec_productUrl', p.Product_URL__c);
            fields.put('ec_in_stock', p.In_Stock__c);

            Map<String, Object> doc = new Map<String, Object>{
                'title' => p.Name,
                'fields' => fields
            };
            updateArr.add(new Map<String, Object>{
                'documentId' => (String) (p.StockKeepingUnit != null ? p.StockKeepingUnit : (String)p.Id),
                'document' => doc
            });
        }
        return JSON.serialize(new Map<String, Object>{ 'update' => updateArr });
    }

    public virtual String buildPartialMergeNdjson(Map<String, Decimal> priceBySku, Map<String, Boolean> inStockBySku) {
        List<Object> mergeArr = new List<Object>();
        Set<String> skus = new Set<String>();
        if (priceBySku != null) {
            skus.addAll(priceBySku.keySet());
        }
        if (inStockBySku != null) {
            skus.addAll(inStockBySku.keySet());
        }
        for (String sku : skus) {
            Map<String, Object> fields = new Map<String, Object>();
            if (priceBySku != null && priceBySku.containsKey(sku)) {
                fields.put('ec_price', priceBySku.get(sku));
            }
            if (inStockBySku != null && inStockBySku.containsKey(sku)) {
                fields.put('ec_in_stock', inStockBySku.get(sku));
            }
            mergeArr.add(new Map<String, Object>{
                'documentId' => sku,
                'document' => new Map<String, Object>{ 'fields' => fields }
            });
        }
        return JSON.serialize(new Map<String, Object>{ 'merge' => mergeArr });
    }

    /**
     * Builds an array like ["Level1","Level1>Level2","Level1>Level2>Level3","Level1>Level2>Level3>Level4"]
     * derived from Category__c tree via ProductCategory__c junctions.
     */
    protected virtual List<String> buildCategoryPathList(Id productId) {
        List<String> paths = new List<String>();
        for (ProductCategory__c link : [SELECT Category__c, Category__r.Name, Category__r.Parent__c FROM ProductCategory__c WHERE Product__c = :productId]) {
            paths.addAll(computeAllPaths(link.Category__c));
        }
        return new List<String>(new Set<String>(paths));
    }

    private List<String> computeAllPaths(Id leafCategoryId) {
        List<Category__c> chain = new List<Category__c>();
        Id cur = leafCategoryId;
        while (cur != null) {
            Category__c c = [SELECT Id, Name, Parent__c FROM Category__c WHERE Id = :cur LIMIT 1];
            chain.add(c);
            cur = c.Parent__c;
        }
        chain.reverse();
        List<String> paths = new List<String>();
        List<String> acc = new List<String>();
        for (Category__c c : chain) {
            acc.add(c.Name);
            paths.add(String.join(acc, '>'));
        }
        return paths;
    }
}
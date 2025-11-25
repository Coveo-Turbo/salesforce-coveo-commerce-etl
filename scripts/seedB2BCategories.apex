// Simple data seeding script for B2B Commerce standard objects
// Creates a 4-level category tree and links sample products to the last level.

List<ProductCategory> cats = new List<ProductCategory>();

// Level 1
ProductCategory tools = new ProductCategory(Name = 'Tools');
cats.add(tools);

// Level 2
ProductCategory powerTools = new ProductCategory(Name = 'Power Tools');
cats.add(powerTools);

// Level 3
ProductCategory drills = new ProductCategory(Name = 'Drills');
cats.add(drills);

// Level 4
ProductCategory cordless = new ProductCategory(Name = 'Cordless');
cats.add(cordless);

insert cats;

// Rebuild parent relationships (must be updated after insert)
Map<String, Id> catIds = new Map<String, Id>();
for (ProductCategory c : cats)
  catIds.put(c.Name, c.Id);

// Update hierarchy
powerTools.ParentCategoryId = catIds.get('Tools');
drills.ParentCategoryId = catIds.get('Power Tools');
cordless.ParentCategoryId = catIds.get('Drills');
update new List<ProductCategory>{ powerTools, drills, cordless };

// Link products
List<Product2> prods = [
  SELECT Id, Name
  FROM Product2
  WHERE IsActive = TRUE
  LIMIT 10
];
List<ProductCategoryProduct> links = new List<ProductCategoryProduct>();

for (Product2 p : prods) {
  links.add(
    new ProductCategoryProduct(
      ProductId = p.Id,
      ProductCategoryId = catIds.get('Cordless')
    )
  );
}

if (!links.isEmpty())
  insert links;

System.debug(
  'Seeded 4-level category tree and linked ' + links.size() + ' products.'
);

string COVEO_ORG_ID = 'coveoprofessionalservicesbi4l69nl';
string COVEO_SOURCE_ID = 'coveoprofessionalservicesbi4l69nl-vkfjrttjfkrvln7d7jcaxz2mqm';
Database.executeBatch(
  new ProductCatalogExportBatch(COVEO_ORG_ID, COVEO_SOURCE_ID),
  100
);

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/duration_constants.dart';
import 'package:smooth_app/generic_lib/loading_dialog.dart';
import 'package:smooth_app/helpers/app_helper.dart';
import 'package:smooth_app/query/product_query.dart';

import 'package:smooth_app/query/products_preload_helper.dart';

class OfflineDataPage extends StatefulWidget {
  const OfflineDataPage({Key? key}) : super(key: key);

  @override
  State<OfflineDataPage> createState() => _OfflineDataPageState();
}

/// Updates the product in the localdatabse and returns the total number of products updated
Future<int> updateLocalDatabaseFromServer(BuildContext context) async {
  final LocalDatabase localDatabase = context.read<LocalDatabase>();
  final DaoProduct daoProduct = DaoProduct(localDatabase);

  /// We seperate the products into two lists, one for products that have a knowledge panel
  /// and one for products that don't have a knowledge panel
  final List<String> barcodes = await daoProduct.getAllKeys();
  final List<String> productsWithoutKnowledgePanel = <String>[];
  final List<String> completeProducts = <String>[];
  for (int i = 0; i < barcodes.length; i++) {
    final Product? productFromDb = await daoProduct.get(barcodes[i]);
    if (productFromDb != null && productFromDb.knowledgePanels == null) {
      productsWithoutKnowledgePanel.add(barcodes[i]);
    } else {
      completeProducts.add(barcodes[i]);
    }
  }
  final List<ProductField> fieldsForCompleteProducts = ProductQuery.fields;
  final List<ProductField> fieldsForProductsWithoutKnowledgePanel =
      List<ProductField>.from(
    ProductQuery.fields,
    growable: true,
  );
  fieldsForProductsWithoutKnowledgePanel.remove(ProductField.KNOWLEDGE_PANELS);
  int totalUpdatedProducts = 0;

  /// Config for the products that don't have a knowledge panel
  final ProductSearchQueryConfiguration productSearchQueryConfiguration =
      ProductSearchQueryConfiguration(
    language: ProductQuery.getLanguage(),
    country: ProductQuery.getCountry(),
    fields: fieldsForProductsWithoutKnowledgePanel,
    parametersList: <Parameter>[
      BarcodeParameter.list(productsWithoutKnowledgePanel),
    ],
    version: ProductQuery.productQueryVersion,
  );

  final SearchResult result = await OpenFoodAPIClient.searchProducts(
    ProductQuery.getUser(),
    productSearchQueryConfiguration,
  );
  if (result.products != null) {
    daoProduct.putAll(result.products!);
    totalUpdatedProducts += result.products!.length;
  }

  /// Config for the complete products ie. products that have a knowledge panel
  final ProductSearchQueryConfiguration
      productSearchQueryConfigurationForFullProducts =
      ProductSearchQueryConfiguration(
    language: ProductQuery.getLanguage(),
    country: ProductQuery.getCountry(),
    fields: fieldsForCompleteProducts,
    parametersList: <Parameter>[
      BarcodeParameter.list(completeProducts),
    ],
    version: ProductQuery.productQueryVersion,
  );

  final SearchResult resultForFullProducts =
      await OpenFoodAPIClient.searchProducts(
    ProductQuery.getUser(),
    productSearchQueryConfigurationForFullProducts,
  );
  if (resultForFullProducts.products != null) {
    daoProduct.putAll(resultForFullProducts.products!);
    totalUpdatedProducts += resultForFullProducts.products!.length;
  }
  return totalUpdatedProducts;
}

class _OfflineDataPageState extends State<OfflineDataPage> {
  @override
  Widget build(BuildContext context) {
    // TODO(ashaman999): replaace the header asset with a custom one for this page
    const String headerAsset = 'assets/preferences/main.svg';
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final double backgroundHeight = MediaQuery.of(context).size.height * .20;
    final LocalDatabase localDatabase = context.watch<LocalDatabase>();
    final DaoProduct daoProduct = DaoProduct(localDatabase);
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(appLocalizations.offline_data),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: ListView(
          children: <Widget>[
            Container(
              color: dark ? null : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: SMALL_SPACE),
              child: SvgPicture.asset(
                headerAsset,
                height: backgroundHeight,
                package: AppHelper.APP_PACKAGE,
              ),
            ),
            _StatsWidget(
              daoProduct: daoProduct,
            ),
            _OfflinePageListTile(
              title: appLocalizations.download_data,
              subtitle: appLocalizations.download_top_products,
              onTap: () async {
                final LocalDatabase localDatabase =
                    context.read<LocalDatabase>();
                final DaoProduct daoProduct = DaoProduct(localDatabase);
                final int newlyAddedProducts = await LoadingDialog.run<int>(
                      title: appLocalizations.download_in_progress,
                      context: context,
                      future:
                          PreloadDataHelper(daoProduct).downloadTopProducts(),
                    ) ??
                    0;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      appLocalizations.downloaded_products(newlyAddedProducts),
                    ),
                  ),
                );
                localDatabase.notifyListeners();
              },
              trailing: const Icon(Icons.download),
            ),
            _OfflinePageListTile(
              title: appLocalizations.update_offline_data,
              subtitle: appLocalizations.update_local_database_sub,
              trailing: const Icon(Icons.refresh),
              onTap: () async {
                final int newlyAddedProducts = await LoadingDialog.run<int>(
                      title: appLocalizations.download_in_progress,
                      context: context,
                      future: updateLocalDatabaseFromServer(context),
                    ) ??
                    0;
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        appLocalizations
                            .downloaded_products(newlyAddedProducts),
                      ),
                      duration: SnackBarDuration.brief,
                    ),
                  );
                }
              },
            ),
            _OfflinePageListTile(
              title: appLocalizations.clear_local_database,
              subtitle: appLocalizations.clear_local_database_sub,
              trailing: const Icon(Icons.delete),
              onTap: () async {
                final int totalProductsDeleted = await daoProduct.deleteAll();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        appLocalizations.deleted_products(totalProductsDeleted),
                      ),
                      duration: SnackBarDuration.brief,
                    ),
                  );
                }
                setState(() {});
              },
            ),
            _OfflinePageListTile(
              title: appLocalizations.know_more,
              subtitle: appLocalizations.offline_data_desc,
              trailing: const Icon(Icons.info),
              // ignore: avoid_returning_null_for_void
              onTap: () => null,
            ),
          ],
        ),
      ),
    );
  }
}

// Widget to display the stats of the local databas, ie. the number of products
// in the database and the size of the database
class _StatsWidget extends StatelessWidget {
  const _StatsWidget({
    Key? key,
    required this.daoProduct,
  }) : super(key: key);
  final DaoProduct daoProduct;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations applocalizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SMALL_SPACE),
      child: ListTile(
        title: Text(applocalizations.offline_product_data_title),
        subtitle: FutureBuilder<int>(
          future: daoProduct.getTotalNoOfProducts(),
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return Text(
                applocalizations.available_for_download(snapshot.data!),
              );
            } else {
              return Text(applocalizations.loading);
            }
          },
        ),
        trailing: FutureBuilder<double>(
          future: daoProduct.getEstimatedTotalSizeInMB(),
          builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
            if (snapshot.hasData) {
              return Text('${snapshot.data} MB');
            } else {
              return const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator.adaptive(),
              );
            }
          },
        ),
      ),
    );
  }
}

// Widget to display a list tile with a title, subtitle
// and a trailing widget and an onTap callback for OfflineDataPage
class _OfflinePageListTile extends StatelessWidget {
  const _OfflinePageListTile({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  }) : super(key: key);
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SMALL_SPACE),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

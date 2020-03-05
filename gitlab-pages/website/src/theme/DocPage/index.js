/**
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React, { useState } from 'react';
import {MDXProvider} from '@mdx-js/react';

import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import renderRoutes from '@docusaurus/renderRoutes';
import Layout from '@theme/Layout';
import DocSidebar from '@theme/DocSidebar';
import MDXComponents from '@theme/MDXComponents';
import NotFound from '@theme/NotFound';
import {matchPath} from '@docusaurus/router';

import styles from './styles.module.css';

import SyntaxContext from '@theme/Syntax/SyntaxContext';

function DocPage(props) {
  const {route: baseRoute, docsMetadata, location} = props;
  
  // case-sensitive route such as it is defined in the sidebar
  const currentRoute =
    baseRoute.routes.find(route => {
      return matchPath(location.pathname, route);
    }) || {};
  const {permalinkToSidebar, docsSidebars, version} = docsMetadata;
  const sidebar = permalinkToSidebar[currentRoute.path];
  const {
    siteConfig: {themeConfig = {}} = {},
    isClient,
  } = useDocusaurusContext();
  const {sidebarCollapsible = true} = themeConfig;

  let defaultSyntax = 'pascaligo';
  if (isClient) {
    defaultSyntax = localStorage.getItem('syntax') || defaultSyntax
  }

  const [syntax, setSyntax] = useState(defaultSyntax);

  if (Object.keys(currentRoute).length === 0) {
    return <NotFound {...props} />;
  }

  return (
    <Layout version={version} key={isClient}>
      <SyntaxContext.Provider value={syntax}>        
        <div className={styles.docPage}>
          {sidebar && (
            <div className={styles.docSidebarContainer}>
              <DocSidebar
                docsSidebars={docsSidebars}
                path={currentRoute.path}
                sidebar={sidebar}
                sidebarCollapsible={sidebarCollapsible}
                syntax={syntax}
                onSyntaxChange={l => {
                  localStorage.setItem('syntax', l);
                  setSyntax(l)
                }}
              />
            </div>
          )}
          <main className={styles.docMainContainer}>
            <MDXProvider components={MDXComponents}>
              {renderRoutes(baseRoute.routes)}
            </MDXProvider>
          </main>
        </div>
      </SyntaxContext.Provider>
    </Layout>
  );
}

export default DocPage;

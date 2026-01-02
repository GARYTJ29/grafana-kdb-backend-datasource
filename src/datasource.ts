import { DataQueryRequest, DataQueryResponse, DataSourceInstanceSettings } from '@grafana/data';
import { DataSourceWithBackend, getBackendSrv, getTemplateSrv, toDataQueryResponse } from '@grafana/runtime';
import { Observable, lastValueFrom } from 'rxjs';
import {MyDataSourceOptions, MyQuery, MyVariableQuery} from './types';


export class DataSource extends DataSourceWithBackend<MyQuery, MyDataSourceOptions> {
  constructor(instanceSettings: DataSourceInstanceSettings<MyDataSourceOptions>) {
    super(instanceSettings);
  }

  query(options: DataQueryRequest<MyQuery>): Observable<DataQueryResponse> {
    const templateSrv = getTemplateSrv();
    const interpolatedQueries = options.targets.map(query => ({
      ...query,
      queryText: templateSrv.replace(query.queryText, options.scopedVars),
    }));
    return super.query({ ...options, targets: interpolatedQueries });
  }

  async metricFindQuery(query: MyVariableQuery, options?: any): Promise<any> {
    const templateSrv = getTemplateSrv();
    let timeout = parseInt(query.timeOut, 10)
    const body: any = {
      queries: [
        { datasourceId:this.id,
          orgId: this.id,
          queryText: query.queryText ? templateSrv.replace(query.queryText,options?.scopedVars || {}) : '',
          timeOut: timeout,
        }
      ]
    }

    try {
      const response = await lastValueFrom(
        getBackendSrv().fetch<any>({
          url: '/api/ds/query',
          method: 'POST',
          data: body,
        })
      );

      const parsedResponse = toDataQueryResponse(response);
      let responseValues: any[] = [];

      for (let frame in parsedResponse.data) {
        responseValues = responseValues.concat(
          parsedResponse.data[frame].fields[0].values.toArray().map((x: any) => ({ text: x }))
        );
      }

      return responseValues;
    } catch (err: any) {
      console.log(err);
      if (err) {
        err.isHandled = true; // Avoid extra popup warning
      }
      return [{ text: 'ERROR' }];
    }
  }
}

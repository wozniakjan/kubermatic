package resources

import (
	"net"
	"net/url"
	"path"

	"github.com/kubermatic/api"
	"github.com/kubermatic/api/controller/cluster"
	"github.com/kubermatic/api/controller/template"

	"k8s.io/client-go/pkg/api/v1"
	extensionsv1beta1 "k8s.io/client-go/pkg/apis/extensions/v1beta1"
)

func LoadServiceFile(cc *cluster.clusterController, c *api.Cluster, s string) (*v1.Service, error) {
	t, err := template.ParseFiles(path.Join(cc.masterResourcesPath, s+"-service.yaml"))
	if err != nil {
		return nil, err
	}

	var service v1.Service

	data := struct {
		SecurePort int
	}{
		SecurePort: c.Address.NodePort,
	}

	err = t.Execute(data, &service)

	return &service, err
}

func LoadIngressFile(cc *cluster.clusterController, c *api.Cluster, s string) (*extensionsv1beta1.Ingress, error) {
	t, err := template.ParseFiles(path.Join(cc.masterResourcesPath, s+"-ingress.yaml"))
	if err != nil {
		return nil, err
	}
	var ingress extensionsv1beta1.Ingress
	data := struct {
		DC          string
		ClusterName string
		ExternalURL string
	}{
		DC:          cc.dc,
		ClusterName: c.Metadata.Name,
		ExternalURL: cc.externalURL,
	}
	err = t.Execute(data, &ingress)

	if err != nil {
		return nil, err
	}

	return &ingress, err
}

func LoadDeploymentFile(c *api.Cluster, masterResourcesPath, overwriteHost, dc, s string) (*extensionsv1beta1.Deployment, error) {
	t, err := template.ParseFiles(path.Join(masterResourcesPath, s+"-dep.yaml"))
	if err != nil {
		return nil, err
	}

	var dep extensionsv1beta1.Deployment
	data := struct {
		DC          string
		ClusterName string
	}{
		DC:          dc,
		ClusterName: c.Metadata.Name,
	}
	err = t.Execute(data, &dep)
	return &dep, err
}

func LoadApiserver(c *api.Cluster, masterResourcesPath, overwriteHost, dc, s string) (*extensionsv1beta1.Deployment, error) {
	var data struct {
		AdvertiseAddress string
		SecurePort       int
	}

	if cc.overwriteHost == "" {
		u, err := url.Parse(c.Address.URL)
		if err != nil {
			return nil, err
		}
		addrs, err := net.LookupHost(u.Host)
		if err != nil {
			return nil, err
		}
		data.AdvertiseAddress = addrs[0]
	} else {
		data.AdvertiseAddress = overwriteHost
	}
	data.SecurePort = c.Address.NodePort

	t, err := template.ParseFiles(path.Join(masterResourcesPath, s+"-dep.yaml"))
	if err != nil {
		return nil, err
	}

	var dep extensionsv1beta1.Deployment
	err = t.Execute(data, &dep)
	return &dep, err
}

func LoadPVCFile(cc *cluster.clusterController, c *api.Cluster, s string) (*v1.PersistentVolumeClaim, error) {
	t, err := template.ParseFiles(path.Join(cc.masterResourcesPath, s+"-pvc.yaml"))
	if err != nil {
		return nil, err
	}

	var pvc v1.PersistentVolumeClaim
	data := struct {
		ClusterName string
	}{
		ClusterName: c.Metadata.Name,
	}
	err = t.Execute(data, &pvc)
	return &pvc, err
}
